/// Typed failures surfaced by the API layer.
///
/// UI code switches on [kind] instead of parsing strings, and users never
/// see raw backend exception traces.
enum ApiFailureKind {
  network, // no connection, DNS, connection reset, timeout
  unauthorized, // 401 — session expired or invalid credentials
  forbidden, // 403
  notFound, // 404
  validation, // 422 — field-level errors available
  server, // 5xx
  canceled, // request canceled (user navigated away / debounce)
  unknown,
}

class ApiException implements Exception {
  ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.fieldErrors = const {},
  });

  final ApiFailureKind kind;
  final String message;
  final int? statusCode;

  /// Field-level validation errors from FastAPI 422 responses
  /// (`{detail: [{loc, msg, type}, ...]}`), keyed by field name.
  final Map<String, String> fieldErrors;

  bool get isUnauthorized => kind == ApiFailureKind.unauthorized;

  /// True when the failure should NOT be retried automatically
  /// (non-idempotent or terminal states).
  bool get isTerminal => kind == ApiFailureKind.validation || isUnauthorized;

  @override
  String toString() => 'ApiException($kind, $statusCode): $message';
}
