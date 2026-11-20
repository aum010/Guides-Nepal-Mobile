import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../models/guide.dart';
import 'network_image_view.dart';

/// Circular guide portrait with initials fallback.
class GuideAvatar extends StatelessWidget {
  const GuideAvatar({super.key, required this.guide, this.radius = 26});

  final Guide guide;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (guide.image.isNotEmpty) {
      return NetworkImageView(
        url: guide.image,
        width: radius * 2,
        height: radius * 2,
        borderRadius: BorderRadius.circular(radius),
        semanticsLabel: guide.name,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.surfacePeach,
      child: Text(
        guide.initials,
        style: AppTypography.label.copyWith(color: AppColors.secondary),
      ),
    );
  }
}

/// Host-centric preview card for rails: portrait with a verification mark,
/// name, role, languages and — only when the platform has real reviews —
/// a star line. Never invents a rating for a new guide.
class GuideCard extends StatelessWidget {
  const GuideCard({
    super.key,
    required this.guide,
    this.onTap,
    this.width = 164,
  });

  final Guide guide;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final hasRating = guide.rating > 0 && guide.reviews > 0;

    final accessibleLabel = [
      guide.name,
      if (guide.role.isNotEmpty) guide.role,
      if (hasRating)
        'rated ${guide.rating.toStringAsFixed(1)} from ${guide.reviews} reviews',
      if (guide.verified) 'verified guide',
    ].join(', ');

    return Semantics(
      button: true,
      label: accessibleLabel,
      child: SizedBox(
        width: width,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GuideAvatar(guide: guide, radius: 34),
                      if (guide.verified)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x2 + 2),
                  Text(
                    guide.name,
                    style: AppTypography.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  if (guide.role.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      guide.role,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (hasRating) ...[
                    const SizedBox(height: AppSpacing.x1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 14, color: AppColors.iconRating),
                        const SizedBox(width: 3),
                        Text(
                          guide.rating.toStringAsFixed(1),
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '(${guide.reviews})',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (guide.languages.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      guide.languages.take(3).join(' · '),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
