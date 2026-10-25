import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

enum AppButtonVariant { primary, secondary, outline, ghost }

/// The one button component: consistent heights, 44dp+ targets, and a
/// built-in loading state that blocks duplicate submissions.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.leading,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool loading;
  final Widget? leading;
  final bool expanded;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: variant == AppButtonVariant.primary
                  ? AppColors.textOnAccent
                  : AppColors.primary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.x2),
              ],
              Text(label),
            ],
          );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    );

    final ButtonStyle style;
    switch (variant) {
      case AppButtonVariant.primary:
        style = FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.textOnAccent,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: const Size(
              AppSpacing.minTouchTarget, AppSpacing.minTouchTarget + 6),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
          shape: shape,
          textStyle: AppTypography.label.copyWith(fontSize: 16),
        );
      case AppButtonVariant.secondary:
        style = FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: const Size(
              AppSpacing.minTouchTarget, AppSpacing.minTouchTarget + 6),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
          shape: shape,
          textStyle: AppTypography.label.copyWith(fontSize: 16),
        );
      case AppButtonVariant.outline:
        style = OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          disabledForegroundColor: AppColors.textTertiary,
          side: const BorderSide(color: AppColors.primary, width: 1.4),
          minimumSize: const Size(
              AppSpacing.minTouchTarget, AppSpacing.minTouchTarget + 6),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x6),
          shape: shape,
          textStyle: AppTypography.label.copyWith(fontSize: 16),
        );
      case AppButtonVariant.ghost:
        style = TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: const Size(
              AppSpacing.minTouchTarget, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
          shape: shape,
          textStyle: AppTypography.label,
        );
    }

    final button = switch (variant) {
      AppButtonVariant.primary || AppButtonVariant.secondary =>
        FilledButton(onPressed: _enabled ? onPressed : null, style: style, child: child),
      AppButtonVariant.outline =>
        OutlinedButton(onPressed: _enabled ? onPressed : null, style: style, child: child),
      AppButtonVariant.ghost =>
        TextButton(onPressed: _enabled ? onPressed : null, style: style, child: child),
    };

    return Semantics(
      button: true,
      label: label,
      enabled: _enabled,
      child: loading
          ? ExcludeSemantics(child: button)
          : (expanded
              ? SizedBox(width: double.infinity, child: button)
              : button),
    );
  }
}
