import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../models/experience.dart';
import 'network_image_view.dart';

/// The standard experience card: rounded photography, a save control that
/// never covers the title, scannable metadata, and an explicit per-person
/// price. Cards earn a "Guest favourite" ribbon purely from real ratings —
/// no listing is highlighted without the reviews to back it.
class ExperienceCard extends StatelessWidget {
  const ExperienceCard({
    super.key,
    required this.experience,
    this.onTap,
    this.isSaved = false,
    this.onToggleSave,
    this.width,
    this.compact = false,
    this.imageHeight,
  });

  final Experience experience;
  final VoidCallback? onTap;
  final bool isSaved;
  final VoidCallback? onToggleSave;
  final double? width;
  final bool compact;

  /// Photo height — tall for editorial rails, shorter inside grid cells so
  /// the text block always fits without overflow.
  final double? imageHeight;

  static const double _guestFavouriteMinRating = 4.7;
  static const int _guestFavouriteMinReviews = 10;

  @override
  Widget build(BuildContext context) {
    final rating = experience.rating;
    final reviews = experience.reviewCount;
    final meta = [
      if (experience.city != null && experience.city!.isNotEmpty)
        experience.city!,
      if (experience.duration != null && experience.duration!.isNotEmpty)
        experience.duration!,
    ].join(' · ');

    final isGuestFavourite = rating != null &&
        rating >= _guestFavouriteMinRating &&
        reviews != null &&
        reviews >= _guestFavouriteMinReviews;

    final accessibleLabel = [
      experience.title,
      if (experience.city != null) 'in ${experience.city}',
      if (rating != null)
        'rated ${rating.toStringAsFixed(1)} out of 5'
            '${reviews != null ? ' from ${Formatters.reviewCount(reviews)}' : ''}',
      if (experience.price != null)
        '${Formatters.price(experience.price!)} per person',
    ].join(', ');

    return Semantics(
      button: true,
      label: accessibleLabel,
      child: RepaintBoundary(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Positioned.fill(
                      child: Hero(
                        tag: 'experience-image-${experience.slug}',
                        child: NetworkImageView(
                          url: experience.heroImage,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusLg),
                          semanticsLabel: experience.title,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: width ?? double.infinity,
                      height: imageHeight ?? (compact ? 110 : 164),
                    ),
                    // The ribbon sits at the bottom-left of the photo, the one
                    // corner the save control never occupies. Pinning it top-
                    // left collided with the heart on a two-up grid cell and
                    // squeezed "Guest favourite" down to "Guest favou…"; one
                    // consistent corner needs neither compromise.
                    if (isGuestFavourite && !compact)
                      Positioned(
                        left: AppSpacing.x2,
                        right: AppSpacing.x2,
                        bottom: AppSpacing.x2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _GuestFavouriteBadge(
                            semanticsLabel:
                                'Guest favourite, rated ${rating.toStringAsFixed(1)} '
                                'from ${Formatters.reviewCount(reviews)}',
                          ),
                        ),
                      ),
                    if (onToggleSave != null)
                      Positioned(
                        top: AppSpacing.x2,
                        right: AppSpacing.x2,
                        child: Semantics(
                          button: true,
                          label: isSaved
                              ? 'Remove ${experience.title} from saved'
                              : 'Save ${experience.title}',
                          child: Material(
                            color: AppColors.onImageSurface,
                            shape: const CircleBorder(),
                            shadowColor: AppColors.onImageShadow,
                            elevation: 2,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onToggleSave,
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.x2 - 1),
                                child: Icon(
                                  isSaved
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 19,
                                  color: isSaved
                                      ? AppColors.favoriteActive
                                      : AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x2 + 2),
                Text(
                  experience.title,
                  style: AppTypography.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],                    const SizedBox(height: AppSpacing.x1 + 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (rating != null)
                          // Scales down as one unit in narrow grid cells so
                          // star, rating and count shrink gracefully instead
                          // of overflowing or ellipsizing mid-word. The full
                          // "N reviews" phrase lives in the Semantics label.
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment:
                                    CrossAxisAlignment.center,
                                children: [
                                  const Icon(Icons.star_rounded,
                                      size: 17, color: AppColors.iconRating),
                                  const SizedBox(width: 3),
                                  Text(
                                    rating.toStringAsFixed(1),
                                    style: AppTypography.small
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  if (reviews != null) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '(${Formatters.reviewCountShort(reviews)})',
                                      style: AppTypography.caption,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: Text(
                              'New on Guides Nepal',
                              style: AppTypography.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (experience.price != null) ...[
                          const SizedBox(width: AppSpacing.x1),
                          Text(
                            Formatters.pricePerPerson(experience.price!),
                            style: AppTypography.priceSmall,
                          ),
                        ],
                      ],
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Airbnb-style "Guest favourite" ribbon pinned over the photo.
class _GuestFavouriteBadge extends StatelessWidget {
  const _GuestFavouriteBadge({required this.semanticsLabel});

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: AppColors.onImageSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_rounded,
                size: 11, color: AppColors.favoriteActive),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Guest favourite',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.badge.copyWith(
                  color: AppColors.primary,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
