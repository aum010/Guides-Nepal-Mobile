"""Coverage for the chat endpoints: Ollama, OpenAI, auto-detection, the
built-in replies and the streaming fallbacks.

Every provider call is faked at the ``httpx.AsyncClient`` level so the tests
never touch a network, and each branch is pinned by monkeypatching settings.
"""

from collections.abc import AsyncIterator
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.config import settings

AI = "/api/v1/ai"


class _FakeResponse:
    def __init__(
        self, status_code: int = 200, payload: Any = None, text: str = ""
    ) -> None:
        self.status_code = status_code
        self._payload = payload if payload is not None else {}
        self.text = text

    def json(self) -> Any:
        return self._payload


class _FakeStream:
    def __init__(self, lines: list[str]) -> None:
        self._lines = lines

    async def __aenter__(self) -> "_FakeStream":
        return self

    async def __aexit__(self, *exc: Any) -> None:
        return None

    async def aiter_lines(self) -> AsyncIterator[str]:
        for line in self._lines:
            yield line


class _FakeClient:
    """Stand-in for ``httpx.AsyncClient`` covering get/post/stream."""

    def __init__(
        self,
        *,
        get: Any = None,
        post: Any = None,
        stream_lines: list[str] | None = None,
        raise_on: str | None = None,
    ) -> None:
        self._get = get if get is not None else _FakeResponse(200)
        self._post = post if post is not None else _FakeResponse(200)
        self._stream_lines = stream_lines or []
        self._raise_on = raise_on

    async def __aenter__(self) -> "_FakeClient":
        return self

    async def __aexit__(self, *exc: Any) -> None:
        return None

    async def get(self, url: str, params: Any = None) -> _FakeResponse:
        if self._raise_on == "get":
            raise httpx.ConnectError("unreachable")
        if callable(self._get):
            response: _FakeResponse = self._get(url, params)
            return response
        return self._get

    async def post(self, url: str, headers: Any = None, json: Any = None) -> Any:
        if self._raise_on == "post":
            raise httpx.TransportError("model down")
        if callable(self._post):
            return self._post(url, headers, json)
        return self._post

    def stream(
        self, method: str, url: str, headers: Any = None, json: Any = None
    ) -> Any:
        return _FakeStream(self._stream_lines)


class _ExplodingStream:
    async def __aenter__(self) -> "_ExplodingStream":
        return self

    async def __aexit__(self, *exc: Any) -> None:
        return None

    def aiter_lines(self) -> Any:
        raise httpx.TransportError("stream down")


class _ExplodingClient(_FakeClient):
    """Fails when the provider stream is opened."""

    def stream(
        self, method: str, url: str, headers: Any = None, json: Any = None
    ) -> Any:
        return _ExplodingStream()


def _install(monkeypatch: pytest.MonkeyPatch, client: _FakeClient) -> list[Any]:
    """Patch ``httpx.AsyncClient`` and record the instances created."""
    created: list[Any] = []

    def factory(*args: Any, **kwargs: Any) -> _FakeClient:
        created.append((args, kwargs))
        return client

    monkeypatch.setattr(httpx, "AsyncClient", factory)
    return created


@pytest.fixture(autouse=True)
def _no_live_providers(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "OPENAI_API_KEY", None)
    monkeypatch.setattr(settings, "OLLAMA_URL", None)
    monkeypatch.setattr(settings, "AI_PROVIDER", "openai")


def _chat(client: TestClient, message: str, **extra: Any) -> Any:
    payload = {"messages": [{"role": "user", "content": message}], **extra}
    return client.post(f"{AI}/chat", json=payload)


class TestChatValidation:
    def test_requires_a_user_message(self, client: TestClient) -> None:
        response = client.post(
            f"{AI}/chat", json={"messages": [{"role": "assistant", "content": "hi"}]}
        )
        assert response.status_code == 400
        assert response.json()["detail"] == "No user message provided"

    def test_rejects_an_unknown_role(self, client: TestClient) -> None:
        response = client.post(
            f"{AI}/chat", json={"messages": [{"role": "robot", "content": "hi"}]}
        )
        assert response.status_code == 422


class TestChatOllama:
    def test_reply_is_returned(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "ollama")
        fake = _FakeClient(
            post=_FakeResponse(200, {"message": {"content": "Namaste from Ollama"}})
        )
        created = _install(monkeypatch, fake)

        response = _chat(client, "hello", model="llama3.2", temperature=0.2)

        assert response.status_code == 200
        assert response.json() == {"reply": "Namaste from Ollama"}
        assert created  # the client was constructed

    def test_upstream_error_status_is_propagated(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "ollama")
        _install(monkeypatch, _FakeClient(post=_FakeResponse(503, text="loading")))

        response = _chat(client, "hello")

        assert response.status_code == 503
        assert "loading" in response.json()["detail"]

    def test_empty_reply_is_a_server_error(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "ollama")
        _install(monkeypatch, _FakeClient(post=_FakeResponse(200, {"message": {}})))

        response = _chat(client, "hello")

        assert response.status_code == 500
        assert "Empty response" in response.json()["detail"]

    def test_transport_failure_falls_back_to_the_builtin_reply(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "ollama")
        _install(monkeypatch, _FakeClient(raise_on="post"))

        response = _chat(client, "namaste")

        assert response.status_code == 200
        assert "Namaste" in response.json()["reply"]


class TestChatOpenAI:
    def test_completion_is_returned(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "sk-test")
        _install(
            monkeypatch,
            _FakeClient(
                post=_FakeResponse(
                    200, {"choices": [{"message": {"content": "From GPT"}}]}
                )
            ),
        )

        response = _chat(client, "hello")

        assert response.status_code == 200
        assert response.json() == {"reply": "From GPT"}

    def test_upstream_error_status_is_propagated(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "sk-test")
        _install(monkeypatch, _FakeClient(post=_FakeResponse(429, text="rate limited")))

        response = _chat(client, "hello")

        assert response.status_code == 429
        assert "rate limited" in response.json()["detail"]


class TestChatAutoDetection:
    def test_a_running_ollama_is_detected(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "auto")
        fake = _FakeClient(
            get=_FakeResponse(200, {"models": []}),
            post=_FakeResponse(200, {"message": {"content": "Local model"}}),
        )
        _install(monkeypatch, fake)

        response = _chat(client, "hi")

        assert response.json() == {"reply": "Local model"}

    def test_a_missing_ollama_falls_back(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "auto")
        _install(monkeypatch, _FakeClient(raise_on="get"))

        response = _chat(client, "hello")

        assert response.status_code == 200
        assert "Namaste" in response.json()["reply"]

    def test_a_non_200_ping_falls_back(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "auto")
        _install(monkeypatch, _FakeClient(get=_FakeResponse(500)))

        response = _chat(client, "hello")

        assert response.status_code == 200
        assert response.json()["reply"]


class TestBuiltinReplies:
    def test_live_temperature_for_kathmandu(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        _install(
            monkeypatch,
            _FakeClient(get=_FakeResponse(200, {"current": {"temperature_2m": 21.5}})),
        )

        response = _chat(client, "what is the temperature in kathmandu?")

        assert response.json()["reply"] == "Kathmandu right now: ~21.5°C."

    def test_temperature_falls_back_when_the_weather_api_fails(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        _install(monkeypatch, _FakeClient(raise_on="get"))

        response = _chat(client, "weather in kathmandu")

        assert "18–26°C" in response.json()["reply"]

    def test_temperature_falls_back_on_an_error_status(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        _install(monkeypatch, _FakeClient(get=_FakeResponse(500)))

        response = _chat(client, "weather in kathmandu")

        assert "18–26°C" in response.json()["reply"]

    def test_temperature_without_a_reading_falls_back(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        _install(monkeypatch, _FakeClient(get=_FakeResponse(200, {"current": {}})))

        response = _chat(client, "weather in kathmandu")

        assert "18–26°C" in response.json()["reply"]

    def test_kathmandu_time_is_answered(self, client: TestClient) -> None:
        response = _chat(client, "what time is it in kathmandu?")

        assert "UTC+5:45" in response.json()["reply"]

    def test_food_questions(self, client: TestClient) -> None:
        response = _chat(client, "where can I eat momos?")

        assert "Newari" in response.json()["reply"]

    def test_culture_questions(self, client: TestClient) -> None:
        response = _chat(client, "tell me about the temples")

        assert "heritage walk" in response.json()["reply"]

    def test_adventure_questions(self, client: TestClient) -> None:
        response = _chat(client, "I want to go trekking")

        assert "Feeling adventurous" in response.json()["reply"]

    def test_greetings(self, client: TestClient) -> None:
        response = _chat(client, "namaste")

        assert "Namaste!" in response.json()["reply"]

    def test_generic_questions_get_a_prompt_for_detail(
        self, client: TestClient
    ) -> None:
        response = _chat(client, "I am planning a trip")

        assert "Tell me a bit more" in response.json()["reply"]


class TestChatStream:
    def test_falls_back_to_a_canned_reply_without_a_provider(
        self, client: TestClient
    ) -> None:
        response = client.post(
            f"{AI}/chat/stream",
            json={"messages": [{"role": "user", "content": "hello"}]},
        )

        assert response.status_code == 200
        assert response.headers["content-type"].startswith("text/plain")
        assert "ready to help" in response.text

    def test_ollama_lines_are_streamed(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "ollama")
        lines = [
            "",
            '{"message": {"content": "Na"}}',
            '{"message": {"content": "maste"}}',
            '{"response": "!"}',
            "not-json",
            '{"message": {}}',
        ]
        _install(monkeypatch, _FakeClient(stream_lines=lines))

        response = client.post(
            f"{AI}/chat/stream",
            json={"messages": [{"role": "user", "content": "hello"}]},
        )

        assert response.text == "Namaste!"

    def test_openai_sse_lines_are_streamed(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "OPENAI_API_KEY", "sk-test")
        lines = [
            "event: ping",
            'data: {"choices": [{"delta": {"content": "Hel"}}]}',
            'data: {"choices": [{"delta": {"content": "lo"}}]}',
            'data: {"choices": [{"delta": {}}]}',
            "data: not-json",
            "data: [DONE]",
            'data: {"choices": [{"delta": {"content": "ignored"}}]}',
        ]
        _install(monkeypatch, _FakeClient(stream_lines=lines))

        response = client.post(
            f"{AI}/chat/stream",
            json={"messages": [{"role": "user", "content": "hello"}]},
        )

        assert response.text == "Hello"

    def test_stream_errors_fall_back_to_a_live_temperature(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "ollama")
        _install(
            monkeypatch,
            _ExplodingClient(
                get=_FakeResponse(200, {"current": {"temperature_2m": 19.0}})
            ),
        )

        response = client.post(
            f"{AI}/chat/stream",
            json={"messages": [{"role": "user", "content": "weather in kathmandu"}]},
        )

        assert "about 19.0" in response.text

    def test_stream_errors_fall_back_to_the_canned_weather_text(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "ollama")
        _install(monkeypatch, _ExplodingClient(raise_on="get"))

        response = client.post(
            f"{AI}/chat/stream",
            json={"messages": [{"role": "user", "content": "weather in kathmandu"}]},
        )

        assert "fetch the exact number" in response.text

    def test_stream_errors_fall_back_to_the_generic_reply(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "AI_PROVIDER", "ollama")
        _install(monkeypatch, _ExplodingClient())

        response = client.post(
            f"{AI}/chat/stream",
            json={"messages": [{"role": "user", "content": "hello"}]},
        )

        assert "ready to help" in response.text
