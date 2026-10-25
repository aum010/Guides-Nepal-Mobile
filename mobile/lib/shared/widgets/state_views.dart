import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../l10n/app_strings.dart';
import 'app_button.dart';

/// A single skeleton block. Pulses gently; motion is disabled when the
/// system requests reduced motion.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppSpacing.radiusSm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      return _box(0.6);
    }
    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: _box(1),
    );
  }

  Widget _box(double opacity) => Opacity(
        opacity: opacity,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      );
}

/// Skeleton layout matching the experience card — reserves space so lists
/// don't jump when data arrives.
class ExperienceCardSkeleton extends StatelessWidget {
  const ExperienceCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(height: 160, radius: AppSpacing.radiusLg),
        const SizedBox(height: AppSpacing.x3),
        const SkeletonBox(width: 180, height: 14),
        const SizedBox(height: AppSpacing.x2),
        const SkeletonBox(width: 120, height: 12),
        const SizedBox(height: AppSpacing.x3),
        const SkeletonBox(width: 70, height: 16),
      ],
    );
  }
}

/// Generic full-area loading list placeholder (never a bare spinner).
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Skeletons render inside scroll-view slivers and Columns where the
      // main axis is unbounded; shrink-wrapping sizes them to their content
      // in every context instead of demanding a bounded height.
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppSpacing.gutter),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.x5),
      itemBuilder: (_, __) => const ExperienceCardSkeleton(),
    );
  }
}

/// Empty state with an optional action.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.explore_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.surfacePeach,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: AppColors.secondary),
            ),
            const SizedBox(height: AppSpacing.x5),
            Text(title,
                style: AppTypography.h3, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.x2),
            Text(
              message,
              style: AppTypography.body
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.x6),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state with a retry affordance. Never surfaces backend traces.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.wifi_off_rounded,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.x4),
            Text(
              message,
              style: AppTypography.body
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.x5),
              AppButton(
                label: AppStrings.retry,
                onPressed: onRetry,
                variant: AppButtonVariant.outline,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
