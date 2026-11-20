import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Spacing, radius and layout tokens.
///
/// One consistent scale for all screens — components must not invent
/// one-off paddings or radii.
abstract final class AppSpacing {
  // 4-8-12-16-20-24-32-40-48-64 scale
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;

  // Screen gutter
  static const double gutter = 20;

  // Minimum touch target (iOS HIG / Material accessibility guidance)
  static const double minTouchTarget = 44;

  // Radii — deliberate, not everything is a pill
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusXxl = 24;
  static const double radiusPill = 999;
}

/// Shared elevation presets. Two levels only — a marketplace app reads
/// cleaner with a flat hierarchy: content sits on the canvas, and only
/// truly floating chrome (nav bar, search bar, booking bar) lifts.
abstract final class AppShadows {
  /// Resting cards and inputs: felt, not seen.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.shadowTint,
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// Floating chrome that overlays content or imagery.
  static const List<BoxShadow> floating = [
    BoxShadow(
      color: AppColors.shadowTintStrong,
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -4,
    ),
  ];
}
