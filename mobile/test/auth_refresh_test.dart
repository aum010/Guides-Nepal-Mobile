import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/core/network/api_exception.dart';
import 'package:guides_nepal/core/network/auth_interceptor.dart';
import 'package:guides_nepal/core/storage/token_storage.dart';
import 'package:guides_nepal/features/auth/auth_repository.dart';

/// In-memory [TokenStorage] — secure storage has no plugin in tests, and the
/// repository only uses the read/write/clear surface.
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

Map<String, dynamic> _userJson({required String email, int id = 7}) => {
      'id': id,
      'email': email,
      'firstName': 'Test',
      'lastName': 'Traveler',
      'role': 'traveler',
      'is_active': true,
    };

Map<String, dynamic> _tokenResponse({required String access, required String refresh}) =>
    {
      'access_token': access,
      'refresh_token': refresh,
      'token_type': 'bearer',
      'user': _userJson(email: 'traveler@example.com'),
    };

ApiException _unauthorized() => ApiException(
      kind: ApiFailureKind.unauthorized,
      statusCode: 401,
      message: 'Your session has expired. Please sign in again.',
    );

/// Scripted API: each queued entry for `/profile/me` and `/auth/refresh` is
/// either a response body (success) or an [ApiException] (failure).
class _FakeAuthApi extends ApiClient {
  // The interceptor persists tokens itself; point it at the same in-memory
  // storage the repository uses so no platform channel is touched.
  _FakeAuthApi(TokenStorage storage)
      : super(authInterceptor: AuthInterceptor(tokenStorage: storage));

  final List<Object> meQueue = [];
  final List<Object> refreshQueue = [];
  final List<Object> logoutQueue = [];
  final List<String> calls = [];
  Map<String, Object?>? logoutBody;

  Response<dynamic> _next(List<Object> queue, String label) {
    if (queue.isEmpty) {
      throw ApiException(kind: ApiFailureKind.network, message: 'empty $label');
    }
    final entry = queue.removeAt(0);
    if (entry is ApiException) throw entry;
    return Response<dynamic>(
      data: entry,
      statusCode: 200,
      requestOptions: RequestOptions(path: label),
    );
  }

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    calls.add('GET $path');
    if (path != '/profile/me') {
      throw ApiException(kind: ApiFailureKind.notFound, message: 'GET $path');
    }
    return _next(meQueue, '/profile/me');
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    calls.add('POST $path');
    if (path == '/auth/refresh') return _next(refreshQueue, '/auth/refresh');
    if (path == '/auth/logout') {
      logoutBody = (data as Map?)?.cast<String, Object?>();
      return _next(logoutQueue, '/auth/logout');
    }
    if (path == '/auth/logout-all') return _next(logoutQueue, '/auth/logout-all');
    throw ApiException(kind: ApiFailureKind.notFound, message: 'POST $path');
  }
}

void main() {
  // TokenStorage constructs a FlutterSecureStorage, which needs the binding
  // before any platform channel is touched.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthRepository.restoreSession', () {
    test('healthy session restores without touching /auth/refresh', () async {
      final storage = _MemoryTokenStorage()
        ..data['gn_access_token'] = 'old-access'
        ..data['gn_refresh_token'] = 'refresh-1'
        ..data['gn_user_json'] = '{}';
      final api = _FakeAuthApi(storage)
        ..meQueue.add(_userJson(email: 'traveler@example.com'));

      final state = await AuthRepository(api, storage).restoreSession();

      expect(state.isAuthenticated, isTrue);
      expect(state.user?.email, 'traveler@example.com');
      expect(api.calls, ['GET /profile/me']);
    });

    test('expired access token is exchanged via /auth/refresh', () async {
      final storage = _MemoryTokenStorage()
        ..data['gn_access_token'] = 'expired-access'
        ..data['gn_refresh_token'] = 'refresh-1'
        ..data['gn_user_json'] = '{}';
      final api = _FakeAuthApi(storage)
        ..meQueue.add(_unauthorized())
        ..refreshQueue
            .add(_tokenResponse(access: 'new-access', refresh: 'refresh-2'));

      final state = await AuthRepository(api, storage).restoreSession();

      expect(state.isAuthenticated, isTrue);
      expect(state.user?.email, 'traveler@example.com');
      expect(api.calls, ['GET /profile/me', 'POST /auth/refresh']);
      // The rotated pair replaces the stale one on disk.
      expect(storage.data['gn_access_token'], 'new-access');
      expect(storage.data['gn_refresh_token'], 'refresh-2');
    });

    test('rejected refresh token signs out and clears the session', () async {
      final storage = _MemoryTokenStorage()
        ..data['gn_access_token'] = 'expired-access'
        ..data['gn_refresh_token'] = 'stale-refresh'
        ..data['gn_user_json'] = '{}';
      final api = _FakeAuthApi(storage)
        ..meQueue.add(_unauthorized())
        ..refreshQueue.add(_unauthorized());

      final state = await AuthRepository(api, storage).restoreSession();

      expect(state.isAuthenticated, isFalse);
      expect(storage.data, isEmpty);
    });

    test('missing refresh token signs out without a refresh call', () async {
      final storage = _MemoryTokenStorage()
        ..data['gn_access_token'] = 'expired-access';
      final api = _FakeAuthApi(storage)..meQueue.add(_unauthorized());

      final state = await AuthRepository(api, storage).restoreSession();

      expect(state.isAuthenticated, isFalse);
      expect(api.calls, ['GET /profile/me']);
      expect(storage.data, isEmpty);
    });

    test('network failure during refresh signs out cleanly', () async {
      final storage = _MemoryTokenStorage()
        ..data['gn_access_token'] = 'expired-access'
        ..data['gn_refresh_token'] = 'refresh-1'
        ..data['gn_user_json'] = '{}';
      final api = _FakeAuthApi(storage)
        ..meQueue.add(_unauthorized())
        ..refreshQueue.add(ApiException(
          kind: ApiFailureKind.network,
          message: 'Could not reach Guides Nepal. Check your connection.',
        ));

      final state = await AuthRepository(api, storage).restoreSession();

      expect(state.isAuthenticated, isFalse);
      expect(storage.data, isEmpty);
    });

    test('logout revokes the refresh token, then clears the session', () async {
      final storage = _MemoryTokenStorage()
        ..data['gn_access_token'] = 'access'
        ..data['gn_refresh_token'] = 'refresh-1'
        ..data['gn_user_json'] = '{}';
      final api = _FakeAuthApi(storage)..logoutQueue.add({'status': 'ok'});

      await AuthRepository(api, storage).logout();

      expect(api.logoutBody?['refresh_token'], 'refresh-1');
      expect(storage.data, isEmpty);
    });

    test('logout clears locally even when revocation fails', () async {
      final storage = _MemoryTokenStorage()
        ..data['gn_access_token'] = 'access'
        ..data['gn_refresh_token'] = 'refresh-1'
        ..data['gn_user_json'] = '{}';
      final api = _FakeAuthApi(storage)
        ..logoutQueue.add(ApiException(
          kind: ApiFailureKind.network,
          message: 'Could not reach Guides Nepal. Check your connection.',
        ));

      await AuthRepository(api, storage).logout();

      expect(storage.data, isEmpty);
    });

    test('logoutEverywhere revokes the account, then clears the session', () async {
      final storage = _MemoryTokenStorage()
        ..data['gn_access_token'] = 'access'
        ..data['gn_refresh_token'] = 'refresh-1'
        ..data['gn_user_json'] = '{}';
      final api = _FakeAuthApi(storage)..logoutQueue.add({'status': 'ok'});

      await AuthRepository(api, storage).logoutEverywhere();

      expect(api.calls, ['POST /auth/logout-all']);
      expect(storage.data, isEmpty);
    });

    test('logoutEverywhere clears locally when the call fails', () async {
      final storage = _MemoryTokenStorage()
        ..data['gn_access_token'] = 'access'
        ..data['gn_refresh_token'] = 'refresh-1'
        ..data['gn_user_json'] = '{}';
      final api = _FakeAuthApi(storage)
        ..logoutQueue.add(ApiException(
          kind: ApiFailureKind.network,
          message: 'Could not reach Guides Nepal. Check your connection.',
        ));

      await AuthRepository(api, storage).logoutEverywhere();

      expect(storage.data, isEmpty);
    });

    test('logout without a refresh token skips the network call', () async {
      final storage = _MemoryTokenStorage()..data['gn_access_token'] = 'access';
      final api = _FakeAuthApi(storage);

      await AuthRepository(api, storage).logout();

      expect(api.calls, isEmpty);
      expect(storage.data, isEmpty);
    });

    test('offline fallback still uses the cached identity', () async {
      final storage = _MemoryTokenStorage()
        ..data['gn_access_token'] = 'access'
        ..data['gn_refresh_token'] = 'refresh-1'
        ..data['gn_user_json'] =
            '{"id": 9, "email": "cached@example.com", "role": "traveler"}';
      final api = _FakeAuthApi(storage)..meQueue.add(ApiException(
            kind: ApiFailureKind.network,
            message: 'Could not reach Guides Nepal. Check your connection.',
          ));

      final state = await AuthRepository(api, storage).restoreSession();

      expect(state.isAuthenticated, isTrue);
      expect(state.user?.email, 'cached@example.com');
      expect(api.calls, isNot(contains('POST /auth/refresh')));
    });
  });
}
