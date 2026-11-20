import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

export 'app_button.dart';
export 'app_logo.dart';
export 'app_text_field.dart';
export 'city_updates_section.dart';
export 'experience_card.dart';
export 'floating_nav_bar.dart';
export 'guide_card.dart';
export 'network_image_view.dart';
export 'state_views.dart';
export 'status_chip.dart';

/// Page header shared by the primary tabs: title, optional supporting line
/// and an optional trailing action, all on the same gutter and baseline so
/// Home, Explore, Trips, Inbox and Profile start alike.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, AppSpacing.x4, AppSpacing.gutter, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.h1),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    subtitle!,
                    style: AppTypography.body
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.x3),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Section header with optional trailing action (used across Home and
/// destination screens for a consistent rhythm).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.h3),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTypography.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondary,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.only(left: AppSpacing.x3),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(actionLabel!, style: AppTypography.label),
            ),
        ],
      ),
    );
  }
}

/// Selectable filter chip used in Explore and destination screens.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x4,
              vertical: AppSpacing.x2 + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 16,
                      color: selected
                          ? AppColors.textOnPrimary
                          : AppColors.secondary),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppTypography.small.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.textOnPrimary
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small labeled chip (category, language, duration…).
class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: AppSpacing.x1 + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfacePeach,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.secondary),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppTypography.small
                .copyWith(color: AppColors.primary, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
