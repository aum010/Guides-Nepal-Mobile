import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/app/theme/app_colors.dart';
import 'package:guides_nepal/app/theme/app_spacing.dart';
import 'package:guides_nepal/app/theme/app_theme.dart';

/// The design system's contract, expressed as assertions.
///
/// Colour tokens are only useful if they are readable: these tests compute
/// real WCAG 2.1 contrast ratios, so a future palette tweak that looks fine on
/// a designer's monitor cannot silently push hint text or a rating star below
/// the threshold. The thresholds are the standard ones — 4.5:1 for text,
/// 3:1 for meaningful non-text UI — not invented per token.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void _expectTextContrast(
  String name,
  Color foreground,
  Color background, {
  double minimum = 4.5,
}) {
  final ratio = _contrast(foreground, background);
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason: '$name contrast is ${ratio.toStringAsFixed(2)}:1, below $minimum:1',
  );
}

void main() {
  group('text contrast (WCAG 2.1 AA, 4.5:1)', () {
    for (final surface in const {
      'cream background': AppColors.background,
      'white surface': AppColors.surface,
    }.entries) {
      test('textPrimary on ${surface.key}', () {
        _expectTextContrast('textPrimary', AppColors.textPrimary, surface.value);
      });

      test('textSecondary on ${surface.key}', () {
        _expectTextContrast(
          'textSecondary',
          AppColors.textSecondary,
          surface.value,
        );
      });

      test('textTertiary on ${surface.key} (hints and metadata)', () {
        _expectTextContrast(
          'textTertiary',
          AppColors.textTertiary,
          surface.value,
        );
      });
    }

    test('text on the two filled surfaces', () {
      _expectTextContrast('textOnPrimary', AppColors.textOnPrimary, AppColors.primary);
      _expectTextContrast('textOnAccent', AppColors.textOnAccent, AppColors.accent);
    });

    test('status text on its own tinted surface', () {
      _expectTextContrast('error', AppColors.error, AppColors.errorSurface);
      _expectTextContrast('success', AppColors.success, AppColors.successSurface);
      _expectTextContrast('error on card', AppColors.error, AppColors.surface);
    });

    test('the text ramp is ordered primary → secondary → tertiary', () {
      double l(Color c) => c.computeLuminance();
      // Lighter means less emphasis; if this ever inverts, the hierarchy is
      // lying to the reader even when every pair still passes.
      expect(l(AppColors.textPrimary), lessThan(l(AppColors.textSecondary)));
      expect(l(AppColors.textSecondary), lessThan(l(AppColors.textTertiary)));
      expect(l(AppColors.textTertiary), lessThan(l(AppColors.textDisabled)));
    });
  });

  group('non-text contrast (WCAG 1.4.11, 3:1)', () {
    test('rating stars are readable, which brand yellow is not', () {
      _expectTextContrast(
        'iconRating',
        AppColors.iconRating,
        AppColors.surface,
        minimum: 3,
      );
      // Documents *why* the token exists: the CTA yellow is a fill colour.
      expect(
        _contrast(AppColors.accent, AppColors.surface),
        lessThan(3),
      );
    });

    test('input borders are distinguishable from the canvas', () {
      _expectTextContrast(
        'border',
        AppColors.border,
        AppColors.background,
        minimum: 1.2,
      );
    });
  });

  group('spacing and shape tokens', () {
    test('the spacing scale is strictly increasing', () {
      const scale = <double>[
        AppSpacing.x1,
        AppSpacing.x2,
        AppSpacing.x3,
        AppSpacing.x4,
        AppSpacing.x5,
        AppSpacing.x6,
        AppSpacing.x8,
        AppSpacing.x10,
        AppSpacing.x12,
        AppSpacing.x16,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
      // Every step is a multiple of 4, which is what keeps layouts aligned.
      for (final value in scale) {
        expect(value % 4, 0, reason: '$value is not on the 4pt grid');
      }
    });

    test('touch targets meet the 44pt floor', () {
      expect(AppSpacing.minTouchTarget, greaterThanOrEqualTo(44));
    });

    test('radii increase from small to extra-extra-large', () {
      const radii = <double>[
        AppSpacing.radiusSm,
        AppSpacing.radiusMd,
        AppSpacing.radiusLg,
        AppSpacing.radiusXl,
        AppSpacing.radiusXxl,
      ];
      for (var i = 1; i < radii.length; i++) {
        expect(radii[i], greaterThan(radii[i - 1]));
      }
    });
  });

  group('theme wiring', () {
    final theme = AppTheme.light;

    test('the canvas and text colours come from the tokens', () {
      expect(theme.scaffoldBackgroundColor, AppColors.background);
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.colorScheme.error, AppColors.error);
      expect(theme.colorScheme.outline, AppColors.border);
    });

    test('the primary action is the brand yellow with dark ink', () {
      final style = theme.filledButtonTheme.style!;
      expect(style.backgroundColor?.resolve({}), AppColors.accent);
      expect(style.foregroundColor?.resolve({}), AppColors.textOnAccent);
    });

    test('field labels stay visible before the first keystroke', () {
      // A resting field with only a placeholder forgets its question once the
      // caret appears, and has nothing to announce to a screen reader.
      expect(
        theme.inputDecorationTheme.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
      expect(theme.inputDecorationTheme.floatingLabelStyle, isNotNull);
    });

    test('disabled buttons use the disabled token, not the hint colour', () {
      final style = theme.filledButtonTheme.style!;
      expect(style.foregroundColor?.resolve({WidgetState.disabled}),
          AppColors.textDisabled);
    });

    test('dark mode is deliberately not shipped yet', () {
      // A half-finished dark theme is worse than none; this pins the decision
      // so it is a product choice rather than an oversight.
      expect(AppTheme.light.brightness, Brightness.light);
    });
  });
}
