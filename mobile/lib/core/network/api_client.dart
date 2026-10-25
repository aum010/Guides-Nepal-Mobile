import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// Centralized API client for the Guides Nepal backend (`/api/v1`).
///
/// * One Dio instance — feature code never constructs its own clients.
/// * [AuthInterceptor] attaches the bearer token, renews it silently and
///   maps failures.
/// * Timeouts are bounded. The only automatic retry is the post-refresh
///   replay of a single request that answered 401 (a 401 means the server
///   rejected it before executing, so replaying is safe).
class ApiClient {
  ApiClient({Dio? dio, AuthInterceptor? authInterceptor})
      : _dio = dio ??
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
            ) {
    _authInterceptor = authInterceptor ?? AuthInterceptor();
    _dio!.interceptors.add(_authInterceptor);
    // Lets the interceptor replay a request once its token was renewed.
    _authInterceptor.attachDio(_dio);
  }

  final Dio? _dio;
  late final AuthInterceptor _authInterceptor;

  Dio get dio => _dio!;

  AuthInterceptor get authInterceptor => _authInterceptor;

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _guard(() => dio.get(path, queryParameters: query, cancelToken: cancelToken));

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) =>
      _guard(() => dio.post(path, data: data, cancelToken: cancelToken));

  Future<Response<dynamic>> patch(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) =>
      _guard(() => dio.patch(path, data: data, cancelToken: cancelToken));

  Future<Response<dynamic>> put(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) =>
      _guard(() => dio.put(path, data: data, cancelToken: cancelToken));

  Future<Response<dynamic>> delete(
    String path, {
    CancelToken? cancelToken,
  }) =>
      _guard(() => dio.delete(path, cancelToken: cancelToken));

  /// Executes [request] and normalizes every Dio error into [ApiException].
  Future<Response<dynamic>> _guard(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Public so unit tests and the streaming AI repository can reuse the
  /// exact same error taxonomy.
  static ApiException mapDioException(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      return ApiException(kind: ApiFailureKind.canceled, message: 'Request canceled');
    }
    final response = e.response;
    final status = response?.statusCode;

    if (status == null) {
      final isTimeout = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
      return ApiException(
        kind: ApiFailureKind.network,
        message: isTimeout
            ? 'The request timed out. Please try again.'
            : 'Could not reach Guides Nepal. Check your connection.',
      );
    }

    switch (status) {
      case 401:
        return ApiException(
          kind: ApiFailureKind.unauthorized,
          statusCode: 401,
          message: _detail(e) ?? 'Your session has expired. Please sign in again.',
        );
      case 403:
        return ApiException(
          kind: ApiFailureKind.forbidden,
          statusCode: 403,
          message: _detail(e) ?? 'You do not have access to this action.',
        );
      case 404:
        return ApiException(
          kind: ApiFailureKind.notFound,
          statusCode: 404,
          message: _detail(e) ?? 'Not found.',
        );
      case 400:
      case 409:
      case 422:
        return ApiException(
          kind: ApiFailureKind.validation,
          statusCode: status,
          message: _detail(e) ?? 'Please review your input.',
          fieldErrors: parseFieldErrors(response?.data),
        );
      default:
        if (status >= 500) {
          return ApiException(
            kind: ApiFailureKind.server,
            statusCode: status,
            message: 'Guides Nepal is having trouble right now. Please try again.',
          );
        }
        return ApiException(
          kind: ApiFailureKind.unknown,
          statusCode: status,
          message: _detail(e) ?? 'Unexpected error.',
        );
    }
  }

  static String? _detail(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return null;
  }

  /// FastAPI 422 payload → `{field: message}` map.
  static Map<String, String> parseFieldErrors(Object? data) {
    if (data is! Map) return const {};
    final detail = data['detail'];
    if (detail is! List) return const {};
    final errors = <String, String>{};
    for (final item in detail) {
      if (item is Map) {
        final loc = item['loc'];
        var field = 'field';
        if (loc is List && loc.isNotEmpty) {
          final last = loc.last;
          if (last is String) field = last;
        }
        errors[field] = item['msg']?.toString() ?? 'Invalid value';
      }
    }
    return errors;
  }
}
