import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Guides Nepal typography.
///
/// * `PlayfairDisplay` (bundled, SIL OFL) — editorial display headings that
///   give the product a distinctive travel-editorial voice.
/// * `Inter` (bundled, SIL OFL) — the website's body typeface, used for UI
///   text, metadata, prices and forms.
///
/// Both families are variable fonts; the `wght` axis is set explicitly via
/// [FontVariation] so weights render correctly on every platform.
abstract final class AppTypography {
  static const String displayFamily = 'PlayfairDisplay';
  static const String bodyFamily = 'Inter';

  static TextStyle _display({
    required double size,
    required double height,
    int weight = 700,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: displayFamily,
      fontSize: size,
      height: height,
      color: color,
      letterSpacing: letterSpacing,
      fontWeight: FontWeight.values[weight >= 100 && weight <= 900
          ? (weight ~/ 100) - 1
          : 7],
      fontVariations: [FontVariation('wght', weight.toDouble())],
    );
  }

  static TextStyle _body({
    required double size,
    required double height,
    int weight = 400,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: bodyFamily,
      fontSize: size,
      height: height,
      color: color,
      letterSpacing: letterSpacing,
      fontWeight: FontWeight.values[weight >= 100 && weight <= 900
          ? (weight ~/ 100) - 1
          : 7],
      fontVariations: [FontVariation('wght', weight.toDouble())],
    );
  }

  // Editorial display
  static TextStyle displayLarge =
      _display(size: 40, height: 1.12, weight: 700, letterSpacing: -0.5);
  static TextStyle displayMedium =
      _display(size: 32, height: 1.18, weight: 700, letterSpacing: -0.3);
  static TextStyle displaySmall =
      _display(size: 26, height: 1.22, weight: 600);

  // Headings (Inter, since UI screens read as an app, not a magazine)
  static TextStyle h1 = _body(size: 28, height: 1.2, weight: 700, letterSpacing: -0.5);
  static TextStyle h2 = _body(size: 24, height: 1.25, weight: 700, letterSpacing: -0.3);
  static TextStyle h3 = _body(size: 20, height: 1.3, weight: 600, letterSpacing: -0.2);
  static TextStyle title =
      _body(size: 17, height: 1.35, weight: 600);
  static TextStyle subtitle =
      _body(size: 15, height: 1.4, weight: 600);

  // Body
  static TextStyle body =
      _body(size: 15, height: 1.55, weight: 400);
  static TextStyle bodyMedium =
      _body(size: 15, height: 1.5, weight: 500);
  static TextStyle small = _body(size: 13, height: 1.45, weight: 400);
  static TextStyle caption = _body(
      size: 12, height: 1.4, weight: 400, color: AppColors.textSecondary);
  static TextStyle label =
      _body(size: 14, height: 1.3, weight: 600);
  static TextStyle overline = _body(
      size: 12,
      height: 1.3,
      weight: 600,
      color: AppColors.secondary,
      letterSpacing: 1.1);

  // Numeric emphasis (prices, ratings, booking data)
  static TextStyle price =
      _body(size: 17, height: 1.2, weight: 700);
  static TextStyle priceLarge =
      _body(size: 26, height: 1.15, weight: 700);
}
