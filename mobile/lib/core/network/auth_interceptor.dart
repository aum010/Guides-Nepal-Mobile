import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// Attaches the bearer token to every request and renews it silently.
///
/// When a request returns 401 the interceptor exchanges the stored refresh
/// token at `POST /api/v1/auth/refresh` and replays the original request
/// once with the new access token. Refreshes are single-flight: parallel
/// 401s share one exchange, so a burst of requests never hammers the
/// endpoint. Only when the refresh itself is rejected (or no refresh token
/// is stored) does [onUnauthorized] fire and the caller see
/// [ApiFailureKind.unauthorized].
class AuthInterceptor extends Interceptor {
  AuthInterceptor({TokenStorage? tokenStorage, Dio? refreshDio})
      : _tokenStorage = tokenStorage ?? TokenStorage(),
        _refreshDio = refreshDio ??
            Dio(
              BaseOptions(
                baseUrl: AppConfig.baseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 20),
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  final TokenStorage _tokenStorage;

  /// Dedicated client for the refresh exchange. It carries no interceptor,
  /// so a rejected refresh can never recurse back into this one.
  final Dio _refreshDio;

  /// The client that issued the request — set by [ApiClient] so a refreshed
  /// request can be replayed.
  Dio? _dio;

  Future<bool>? _refreshing;

  /// Marks a replayed request so a second 401 cannot trigger a loop.
  static const _retryKey = 'auth_retry_after_refresh';

  /// Invoked when a 401 cannot be recovered — the router clears the session
  /// and redirects to sign-in.
  void Function()? onUnauthorized;

  String? _cachedToken;

  /// Pre-seed the token after login to avoid an async read on hot paths.
  void setToken(String? token) {
    _cachedToken = token;
    if (token != null) _tokenStorage.saveAccessToken(token);
  }

  /// Called once by [ApiClient] so the interceptor can replay requests.
  void attachDio(Dio dio) => _dio = dio;

  Future<void> primeFromStorage() async {
    _cachedToken ??= await _tokenStorage.readAccessToken();
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = _cachedToken ?? await _tokenStorage.readAccessToken();
    _cachedToken = token;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    final alreadyRetried = options.extra[_retryKey] == true;
    // Sessions are minted and ended by /auth/refresh and /auth/logout; a 401
    // there must not trigger another refresh (or a logout of a logout).
    final isAuthLifecycle = options.path.contains('/auth/refresh') ||
        options.path.contains('/auth/logout');

    if (err.response?.statusCode == 401 && !isAuthLifecycle && !alreadyRetried) {
      _recoverFromUnauthorized(err, handler);
      return;
    }

    if (err.response?.statusCode == 401 && !isAuthLifecycle) {
      // The replay also saw a 401: the session is genuinely over.
      onUnauthorized?.call();
    }
    // Normalized by ApiClient.mapDioException at the call site.
    handler.next(err);
  }

  /// Refreshes the session, then replays [err]'s request exactly once.
  Future<void> _recoverFromUnauthorized(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final refreshed = await _refreshOnce();
    final dio = _dio;
    if (!refreshed || dio == null) {
      onUnauthorized?.call();
      handler.next(err);
      return;
    }

    final options = err.requestOptions..extra[_retryKey] = true;
    if (_cachedToken != null) {
      options.headers['Authorization'] = 'Bearer $_cachedToken';
    }
    try {
      handler.resolve(await dio.fetch(options));
    } on DioException catch (retryError) {
      if (retryError.response?.statusCode == 401) {
        onUnauthorized?.call();
      }
      handler.next(retryError);
    } catch (_) {
      handler.next(err);
    }
  }

  /// One refresh exchange shared by every concurrent 401.
  Future<bool> _refreshOnce() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final future = _performRefresh().whenComplete(() => _refreshing = null);
    _refreshing = future;
    return future;
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final res = await _refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final map = (res.data as Map).cast<String, dynamic>();
      final accessToken = map['access_token'] as String? ?? '';
      final nextRefresh = map['refresh_token'] as String? ?? '';
      final user = map['user'];
      if (accessToken.isEmpty) return false;

      _cachedToken = accessToken;
      if (user is Map && nextRefresh.isNotEmpty) {
        // Persist the rotated pair and identity together; a crash between
        // writes must not leave an access token without its refresh token.
        await _tokenStorage.saveSession(
          accessToken: accessToken,
          refreshToken: nextRefresh,
          userJson: jsonEncode(user),
        );
      } else {
        await _tokenStorage.saveAccessToken(accessToken);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearSession() async {
    _cachedToken = null;
    await _tokenStorage.clear();
  }

  /// Exposed for tests: throws a normalized exception from a raw Dio error.
  static ApiException map(DioException e) => ApiClient.mapDioException(e);
}
