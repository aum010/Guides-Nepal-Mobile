import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

/// Environment configuration.
///
/// The base URL is resolved in this order:
///
/// 1. `--dart-define=API_BASE_URL=https://host/api/v1` (any build, used for
///    staging or a LAN dev machine)
/// 2. Release builds → verified production API (Render)
/// 3. Debug builds → platform development defaults:
///    * Android emulator → `10.0.2.2` (the host loopback alias)
///    * iOS simulator / desktop → `localhost`
///    * Physical devices → pass `API_BASE_URL` with your machine's LAN IP
abstract final class AppConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static const String productionBaseUrl =
      'https://guides-nepal.onrender.com/api/v1';

  static const String devAndroidEmulator = 'http://10.0.2.2:8000/api/v1';
  static const String devLocalhost = 'http://localhost:8000/api/v1';

  /// True when cleartext HTTP may be permitted (development only).
  /// Production networking stays HTTPS-only.
  static bool get allowsCleartext {
    if (_override.isNotEmpty) return _override.startsWith('http://');
    return !kReleaseMode;
  }

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kReleaseMode || kIsWeb) return productionBaseUrl;
    try {
      if (Platform.isAndroid) return devAndroidEmulator;
    } catch (_) {
      // Platform channels unavailable (tests) — fall through.
    }
    return devLocalhost;
  }

  static bool get isProduction => baseUrl == productionBaseUrl;
}
