import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/core/network/api_exception.dart';
import 'package:guides_nepal/core/network/auth_interceptor.dart';
import 'package:guides_nepal/core/storage/token_storage.dart';

/// In-memory [TokenStorage] — secure storage has no plugin in tests, and the
/// interceptor only uses the read/write/clear surface.
class _MemoryTokenStorage extends TokenStorage {
  final Map<String, String> data = {};

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userJson,
  }) async {
    data['gn_access_token'] = accessToken;
    data['gn_refresh_token'] = refreshToken;
    data['gn_user_json'] = userJson;
  }

  @override
  Future<void> saveAccessToken(String token) async =>
      data['gn_access_token'] = token;

  @override
  Future<String?> readAccessToken() async => data['gn_access_token'];

  @override
  Future<String?> readRefreshToken() async => data['gn_refresh_token'];

  @override
  Future<String?> readUserJson() async => data['gn_user_json'];

  @override
  Future<void> clear() async => data.clear();
}

/// Dio transport stub: [respond] decides the reply (and may wait, so tests
/// can hold a response open and observe single-flight behaviour).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.respond);

  final FutureOr<(int, Object?)> Function(RequestOptions options) respond;
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.path);
    final (status, body) = await respond(options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _tokens({String access = 'new-access', String refresh = 'refresh-2'}) => {
      'access_token': access,
      'refresh_token': refresh,
      'token_type': 'bearer',
      'user': {
        'id': 7,
        'email': 'traveler@example.com',
        'firstName': 'Test',
        'lastName': 'Traveler',
        'role': 'traveler',
        'is_active': true,
      },
    };

class _Harness {
  _Harness({
    required FutureOr<(int, Object?)> Function(RequestOptions options) main,
    required FutureOr<(int, Object?)> Function(RequestOptions options) refresh,
    Map<String, String>? stored,
  }) {
    storage = _MemoryTokenStorage();
    if (stored != null) storage.data.addAll(stored);
    mainAdapter = _ScriptedAdapter(main);
    refreshAdapter = _ScriptedAdapter(refresh);
    final refreshDio = Dio(BaseOptions(baseUrl: 'http://api.test/api/v1'))
      ..httpClientAdapter = refreshAdapter;
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test/api/v1'))
      ..httpClientAdapter = mainAdapter;
    client = ApiClient(
      dio: dio,
      authInterceptor:
          AuthInterceptor(tokenStorage: storage, refreshDio: refreshDio),
    );
    client.authInterceptor.onUnauthorized = () => unauthorizedCalls++;
  }

  late final _MemoryTokenStorage storage;
  late final _ScriptedAdapter mainAdapter;
  late final _ScriptedAdapter refreshAdapter;
  late final ApiClient client;
  int unauthorizedCalls = 0;
}

/// 401 until the rotated bearer token arrives, then 200.
FutureOr<(int, Object?)> _expiringEndpoint(RequestOptions options) {
  if (options.headers['Authorization'] == 'Bearer new-access') {
    return (200, {'email': 'traveler@example.com'});
  }
  return (401, {'detail': 'Access token expired'});
}

void main() {
  // TokenStorage constructs a FlutterSecureStorage, which needs the binding
  // before any platform channel is touched.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthInterceptor silent refresh', () {
    test('a 401 is refreshed and the original request replayed once', () async {
      final h = _Harness(
        main: _expiringEndpoint,
        refresh: (_) => (200, _tokens()),
        stored: {'gn_access_token': 'stale', 'gn_refresh_token': 'refresh-1'},
      );

      final res = await h.client.get('/profile/me');

      expect(res.statusCode, 200);
      expect((res.data as Map)['email'], 'traveler@example.com');
      expect(h.mainAdapter.requests.length, 2, reason: 'original + replay');
      expect(h.refreshAdapter.requests.single, contains('/auth/refresh'));
      expect(h.unauthorizedCalls, 0);
      expect(h.storage.data['gn_access_token'], 'new-access');
      expect(h.storage.data['gn_refresh_token'], 'refresh-2');
      expect(h.storage.data['gn_user_json'], contains('traveler@example.com'));
    });

    test('a rejected refresh signs the session out and surfaces 401', () async {
      final h = _Harness(
        main: (o) => (401, {'detail': 'Access token expired'}),
        refresh: (_) => (401, {'detail': 'Invalid refresh token'}),
        stored: {'gn_access_token': 'stale', 'gn_refresh_token': 'stale-too'},
      );

      Object? caught;
      try {
        await h.client.get('/profile/me');
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<ApiException>());
      expect((caught as ApiException).kind, ApiFailureKind.unauthorized);
      expect(h.unauthorizedCalls, 1);
      expect(h.mainAdapter.requests.length, 1, reason: 'no replay');
      expect(h.refreshAdapter.requests.length, 1);
      // The failed exchange must not erase credentials mid-flight — the auth
      // layer decides when to clear storage.
      expect(h.storage.data['gn_refresh_token'], 'stale-too');
    });

    test('no stored refresh token means an immediate sign-out', () async {
      final h = _Harness(
        main: (o) => (401, {'detail': 'Access token expired'}),
        refresh: (_) => (200, _tokens()),
        stored: {'gn_access_token': 'stale'},
      );

      await expectLater(
        h.client.get('/profile/me'),
        throwsA(isA<ApiException>().having(
            (e) => e.kind, 'kind', ApiFailureKind.unauthorized)),
      );
      expect(h.refreshAdapter.requests, isEmpty);
      expect(h.unauthorizedCalls, 1);
    });

    test('parallel 401s share a single refresh exchange', () async {
      final gate = Completer<void>();
      final h = _Harness(
        main: _expiringEndpoint,
        refresh: (_) async {
          await gate.future;
          return (200, _tokens());
        },
        stored: {'gn_access_token': 'stale', 'gn_refresh_token': 'refresh-1'},
      );

      final first = h.client.get('/profile/me');
      final second = h.client.get('/profile/me');
      // Let both requests reach their 401s before the exchange resolves.
      await Future<void>.delayed(Duration.zero);
      gate.complete();

      final responses = await Future.wait([first, second]);
      expect(responses.map((r) => r.statusCode), [200, 200]);
      expect(h.refreshAdapter.requests.length, 1,
          reason: 'one exchange for the whole burst');
      expect(h.unauthorizedCalls, 0);
    });

    test('a non-auth failure is never retried', () async {
      final h = _Harness(
        main: (o) => (500, {'detail': 'boom'}),
        refresh: (_) => (200, _tokens()),
        stored: {'gn_access_token': 'ok', 'gn_refresh_token': 'refresh-1'},
      );

      await expectLater(
        h.client.get('/profile/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiFailureKind.server)),
      );
      expect(h.mainAdapter.requests.length, 1);
      expect(h.refreshAdapter.requests, isEmpty);
      expect(h.unauthorizedCalls, 0);
    });
  });
}
