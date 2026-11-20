import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';

/// Bundled brand artwork.
///
/// Cut from the supplied logo package (`assets/brand/`): the lockup in the
/// launch screen, the circular mark everywhere inside the app. Documents these
/// paths in one place so a screen never hardcodes one and drifts.
abstract final class BrandAssets {
  static const String mark = 'assets/brand/logo_mark.png';
  static const String lockup = 'assets/brand/logo_lockup.png';

  /// The lockup is drawn at 1888×835 — 2.26:1. Widgets that size it by width
  /// use this to reserve exactly the right height instead of guessing.
  static const double lockupAspectRatio = 1888 / 835;
}

/// The circular mark, on its own, at a UI size.
///
/// Drawn from the bundled PNG rather than redrawn with `Icon`s: the four
/// petals are the platform's whole identity, and a lookalike glyph is what
/// makes an app read as "not quite the brand".
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      BrandAssets.mark,
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: AppStrings.appName,
    );
  }
}

/// The full lockup — mark plus the GUIDES NEPAL wordmark.
///
/// Sized by width alone so the artwork's own proportions always hold; the
/// wordmark is navy, so it needs a light ground behind it.
class AppLogoLockup extends StatelessWidget {
  const AppLogoLockup({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      BrandAssets.lockup,
      width: width,
      height: width / BrandAssets.lockupAspectRatio,
      filterQuality: FilterQuality.high,
      semanticLabel: AppStrings.appName,
    );
  }
}
