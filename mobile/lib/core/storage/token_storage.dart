import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure token persistence.
///
/// iOS: Keychain-backed. Android: EncryptedSharedPreferences-backed
/// (flutter_secure_storage default). Tokens and any credential material
/// must only ever be stored here — never in SharedPreferences, source
/// code, or logs.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _kAccess = 'gn_access_token';
  static const _kRefresh = 'gn_refresh_token';
  static const _kUser = 'gn_user_json';

  final FlutterSecureStorage _storage;

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userJson,
  }) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
    await _storage.write(key: _kUser, value: userJson);
  }

  Future<void> saveAccessToken(String token) async =>
      _storage.write(key: _kAccess, value: token);

  Future<String?> readAccessToken() => _storage.read(key: _kAccess);
  Future<String?> readRefreshToken() => _storage.read(key: _kRefresh);
  Future<String?> readUserJson() => _storage.read(key: _kUser);

  /// Clears the whole local session (safe logout).
  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUser);
  }
}
