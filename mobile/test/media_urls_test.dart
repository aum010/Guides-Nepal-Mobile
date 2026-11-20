import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/core/config/app_config.dart';

/// Uploaded photos are stored as paths (`/uploads/...`) so the database never
/// bakes in a host. Every image widget resolves them through
/// `AppConfig.resolveMedia`, so the API origin is applied exactly once.
void main() {
  test('a stored path is resolved against the API origin, not /api/v1', () {
    final resolved = AppConfig.resolveMedia('/uploads/listings/4/ridge.png');

    expect(resolved, '${AppConfig.mediaOrigin}/uploads/listings/4/ridge.png');
    expect(AppConfig.mediaOrigin.endsWith('/api/v1'), isFalse);
    expect(resolved.startsWith('http'), isTrue);
  });

  test('absolute URLs from seeded content pass through untouched', () {
    const url = 'https://images.unsplash.com/photo-1544735716-392fe2489ffa';
    expect(AppConfig.resolveMedia(url), url);
  });

  test('empty values stay empty so the placeholder is shown', () {
    expect(AppConfig.resolveMedia(''), '');
  });
}
