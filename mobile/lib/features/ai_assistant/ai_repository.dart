import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../shared/models/chat_message.dart';
import '../auth/auth_repository.dart';

/// Maila Dai chat against the verified `POST /api/v1/ai/chat` and
/// `POST /api/v1/ai/chat/stream` contracts.
///
/// Streaming payload formats handled (both used by the backend depending on
/// provider): OpenAI-style `data: {...}` / `data: [DONE]` lines and raw
/// Ollama JSON lines. On any streaming failure we fall back to the
/// non-streaming endpoint, mirroring the web widget.
class AiRepository {
  AiRepository(this._client);

  final ApiClient _client;

  /// Yields incremental reply fragments. The caller appends them to the
  /// in-progress assistant message.
  Stream<String> streamChat(List<ChatMessage> history) async* {
    final payload = {
      'messages': [for (final m in history) m.toApiJson()],
    };
    try {
      final response = await _client.dio.post<dynamic>(
        '/ai/chat/stream',
        data: payload,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream, application/x-ndjson'},
        ),
      );
      final stream = response.data as Stream<Uint8List>;
      yield* _parseStream(stream);
    } catch (e) {
      // Fallback: non-streaming endpoint (still a real backend response —
      // never fabricate assistant replies).
      try {
        final reply = await chat(history);
        yield reply;
      } on DioException catch (de) {
        throw ApiClient.mapDioException(de);
      }
    }
  }

  Future<String> chat(List<ChatMessage> history) async {
    final res = await _client.post('/ai/chat', data: {
      'messages': [for (final m in history) m.toApiJson()],
    });
    final data = res.data;
    if (data is Map && data['reply'] is String) {
      return data['reply'] as String;
    }
    throw ApiException(
      kind: ApiFailureKind.unknown,
      message: 'Maila Dai returned an unexpected response.',
    );
  }

  Stream<String> _parseStream(Stream<Uint8List> byteStream) async* {
    final decoder = const Utf8Decoder(allowMalformed: true).bind(byteStream);
    var buffer = '';
    await for (final chunk in decoder) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast(); // keep the trailing partial line
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        var payload = line;
        if (payload.startsWith('data:')) {
          payload = payload.substring(5).trim();
        }
        if (payload.isEmpty || payload == '[DONE]') continue;
        final fragment = _extractText(payload);
        if (fragment != null && fragment.isNotEmpty) {
          yield fragment;
        }
      }
    }
    // Flush any trailing buffered content.
    if (buffer.trim().isNotEmpty && buffer.trim() != '[DONE]') {
      final fragment = _extractText(
        buffer.trim().startsWith('data:')
            ? buffer.trim().substring(5).trim()
            : buffer.trim(),
      );
      if (fragment != null && fragment.isNotEmpty) yield fragment;
    }
  }

  String? _extractText(String jsonLine) {
    try {
      final obj = jsonDecode(jsonLine);
      if (obj is Map) {
        final content =
            ((obj['message'] as Map?)?['content']) ?? obj['response'];
        if (content is String) return content;
        final choices = obj['choices'];
        if (choices is List && choices.isNotEmpty) {
          final delta = (choices.first as Map?)?['delta'];
          final text = (delta as Map?)?['content'];
          if (text is String) return text;
        }
      }
    } catch (_) {
      // Not JSON (e.g. a stray control line) — ignore.
    }
    return null;
  }
}

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(apiClientProvider)),
);
