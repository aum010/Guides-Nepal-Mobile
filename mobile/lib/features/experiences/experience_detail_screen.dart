import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/experience.dart';
import '../../shared/models/guide.dart';
import '../../shared/models/review.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_repository.dart';
import '../favorites/favorites_controller.dart';
import 'experience_repository.dart';

final experienceDetailProvider = FutureProvider.autoDispose
    .family<Experience, String>((ref, slug) {
  return ref.watch(experienceRepositoryProvider).fetchExperience(slug);
});

final experienceReviewsProvider = FutureProvider.autoDispose
    .family<List<Review>, int>((ref, experienceId) {
  return ref.watch(experienceRepositoryProvider).fetchReviews(experienceId);
});

class ExperienceDetailScreen extends ConsumerWidget {
  const ExperienceDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(experienceDetailProvider(slug));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: detail.when(
        loading: () => const _DetailSkeleton(),
        error: (e, _) => ErrorStateView(
          message: e is ApiException ? e.message : AppStrings.offlineBody,
          onRetry: () => ref.invalidate(experienceDetailProvider(slug)),
        ),
        data: (experience) => _DetailBody(experience: experience),
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: 300, radius: 0),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 220, height: 24),
                SizedBox(height: AppSpacing.x3),
                SkeletonBox(width: 160, height: 14),
                SizedBox(height: AppSpacing.x5),
                SkeletonBox(height: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.experience});

  final Experience experience;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoritesControllerProvider);
    final isSaved =
        favs.isSaved(experience.slug, experienceId: experience.id);
    final reviews = ref.watch(experienceReviewsProvider(experience.id));

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 340,
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              leading: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.x2),
                child: _GlassIconButton(
                  tooltip: AppStrings.back,
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 20,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.x2),
                  child: _GlassIconButton(
                    tooltip: isSaved ? 'Remove from saved' : AppStrings.save,
                    icon: isSaved
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    iconColor:
                        isSaved ? AppColors.favoriteActive : AppColors.onImageTextPrimary,
                    onTap: () => _toggleSave(context, ref),
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkImageView(
                      url: experience.heroImage,
                      semanticsLabel: experience.title,
                      fit: BoxFit.cover,
                    ),
                    // Icon-legibility scrim: keeps the glass controls readable
                    // over any photo without darkening the whole image.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment(0, 0.35),
                          colors: [
                            AppColors.imageScrimTop,
                            AppColors.imageScrimBottom,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (experience.city != null)
                      Text(experience.city!.toUpperCase(),
                          style: AppTypography.overline),
                    const SizedBox(height: AppSpacing.x1),
                    Text(experience.title, style: AppTypography.h1),
                    const SizedBox(height: AppSpacing.x3),
                    Row(
                      children: [
                        if (experience.rating != null) ...[
                          const Icon(Icons.star_rounded,
                              size: 18, color: AppColors.iconRating),
                          const SizedBox(width: 4),
                          Text(experience.rating!.toStringAsFixed(1),
                              style: AppTypography.bodyMedium),
                          if (experience.reviewCount != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(${Formatters.reviewCount(experience.reviewCount!)})',
                              style: AppTypography.caption,
                            ),
                          ],
                        ] else
                          Text('New on Guides Nepal',
                              style: AppTypography.caption),
                        const Spacer(),
                        if (experience.duration != null)
                          InfoChip(
                              icon: Icons.schedule_outlined,
                              label: experience.duration!),
                      ],
                    ),
                    if (experience.category != null) ...[
                      const SizedBox(height: AppSpacing.x3),
                      InfoChip(label: experience.category!),
                    ],
                    // Only a published guide listing carries these: its
                    // difficulty and how many seats are actually left.
                    if (experience.difficulty != null ||
                        experience.availableSpots != null) ...[
                      const SizedBox(height: AppSpacing.x3),
                      Wrap(
                        spacing: AppSpacing.x2,
                        runSpacing: AppSpacing.x2,
                        children: [
                          if (experience.difficulty != null)
                            InfoChip(
                              icon: Icons.hiking_outlined,
                              label: experience.difficulty!,
                            ),
                          if (experience.availableSpots != null)
                            InfoChip(
                              icon: Icons.groups_outlined,
                              label: experience.isSoldOut
                                  ? 'Sold out'
                                  : '${experience.availableSpots} of '
                                      '${experience.maxGuests ?? experience.availableSpots} spots left',
                            ),
                        ],
                      ),
                    ],
                    // Up-to-the-moment notes for this experience's city —
                    // sits next to the listing so a change to the day is
                    // seen before the booking bar is used.
                    if (experience.city != null) ...[
                      const SizedBox(height: AppSpacing.x6),
                      CityUpdatesSection(
                        city: experience.city!,
                        title: 'Updates in ${experience.city!}',
                      ),
                    ],
                    if (experience.description.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x6),
                      Text('About this experience',
                          style: AppTypography.h3),
                      const SizedBox(height: AppSpacing.x2),
                      Text(experience.description,
                          style: AppTypography.body.copyWith(
                              color: AppColors.textSecondary)),
                    ],
                    if (experience.itinerary != null &&
                        experience.itinerary!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x6),
                      Text('What we will do', style: AppTypography.h3),
                      const SizedBox(height: AppSpacing.x2),
                      Text(experience.itinerary!,
                          style: AppTypography.body.copyWith(
                              color: AppColors.textSecondary)),
                    ],
                    if (experience.meetingPoint != null &&
                        experience.meetingPoint!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 18, color: AppColors.secondary),
                          const SizedBox(width: AppSpacing.x2),
                          Expanded(
                            child: Text(
                              'Meet at ${experience.meetingPoint!}',
                              style: AppTypography.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.x8),
                    Text('Hosted by', style: AppTypography.h3),
                    const SizedBox(height: AppSpacing.x3),
                    _HostCard(host: experience.host),
                    const SizedBox(height: AppSpacing.x8),
                    Row(
                      children: [
                        Expanded(child: Text('Reviews', style: AppTypography.h3)),
                        if (experience.rating != null &&
                            experience.reviewCount != null) ...[
                          const Icon(Icons.star_rounded,
                              size: 16, color: AppColors.iconRating),
                          const SizedBox(width: 3),
                          Text(
                            '${experience.rating!.toStringAsFixed(1)} · '
                            '${Formatters.reviewCount(experience.reviewCount!)}',
                            style: AppTypography.caption,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    reviews.when(
                      loading: () => const SkeletonList(itemCount: 2),
                      error: (_, __) => Text(
                        'Reviews are unavailable right now.',
                        style: AppTypography.caption,
                      ),
                      data: (list) => list.isEmpty
                          ? Text(
                              'No reviews yet. Be the first after you go.',
                              style: AppTypography.body.copyWith(
                                  color: AppColors.textSecondary),
                            )
                          : Column(
                              children: [for (final r in list) _ReviewTile(review: r)],
                            ),
                    ),
                    const SizedBox(height: AppSpacing.x12),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Bottom booking bar — safe-area aware, never covers content
        // because the scroll view reserves space above it.
        Align(
          alignment: Alignment.bottomCenter,
          child: _BookingBar(experience: experience),
        ),
      ],
    );
  }

  Future<void> _toggleSave(BuildContext context, WidgetRef ref) async {
    if (!ref.read(authControllerProvider).isAuthenticated) {
      context.push('/sign-in');
      return;
    }
    try {
      await ref.read(favoritesControllerProvider.notifier).toggle(experience);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update saved list.')),
        );
      }
    }
  }
}

/// Frosted circular control pinned over the hero photo.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.iconColor = AppColors.onImageTextPrimary,
    this.iconSize = 22,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: AppColors.onImageFillStrong,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.onImageBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: AppSpacing.minTouchTarget,
              height: AppSpacing.minTouchTarget,
              child: Icon(icon, color: iconColor, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}

/// Host-centric card (Withlocals pattern): who you are actually spending
/// the day with, their languages and standing — tappable through to the
/// full guide profile when the API supplied a usable id.
class _HostCard extends StatelessWidget {
  const _HostCard({required this.host});

  final Guide host;

  @override
  Widget build(BuildContext context) {
    final name = host.name;
    if (name.isEmpty) {
      return Text('Host details unavailable',
          style: AppTypography.caption);
    }
    final hasProfile = host.id > 0;
    final hasRating = host.rating > 0 && host.reviews > 0;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasProfile ? () => context.push('/guide/${host.id}') : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Row(
            children: [
              GuideAvatar(guide: host, radius: 30),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: AppTypography.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (host.verified) ...[
                          const SizedBox(width: AppSpacing.x1),
                          const Icon(Icons.verified_rounded,
                              size: 16, color: AppColors.secondary),
                        ],
                      ],
                    ),
                    if (host.role.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        host.role,
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (hasRating) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 13, color: AppColors.iconRating),
                          const SizedBox(width: 3),
                          Text(
                            host.rating.toStringAsFixed(1),
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${host.reviews})',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (host.languages.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Speaks ${host.languages.take(3).join(', ')}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (hasProfile) ...[
                const SizedBox(width: AppSpacing.x1),
                const Icon(Icons.chevron_right_rounded,
                    size: 22, color: AppColors.textTertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final userName = review.userName ?? 'Traveler';
    final initials = userName.trim().isEmpty
        ? '?'
        : userName.trim().split(RegExp(r'\s+')).length > 1
            ? (userName.trim().split(RegExp(r'\s+')).first.substring(0, 1) +
                    userName.trim().split(RegExp(r'\s+')).last.substring(0, 1))
                .toUpperCase()
            : userName.trim().substring(0, 1).toUpperCase();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.x3),
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.surfacePeach,
                child: Text(
                  initials,
                  style: AppTypography.micro.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x2 + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: AppTypography.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      Formatters.dateShort(review.createdAt),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    Icon(
                      i <= review.rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 14,
                      color: AppColors.iconRating,
                    ),
                ],
              ),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x2),
            Text(review.comment!, style: AppTypography.body),
          ],
        ],
      ),
    );
  }
}

class _BookingBar extends StatelessWidget {
  const _BookingBar({required this.experience});

  final Experience experience;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.gutter,
        right: AppSpacing.gutter,
        top: AppSpacing.x4,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.x4,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (experience.price != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        Formatters.price(experience.price!),
                        style: AppTypography.priceMd,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '/ person',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  )
                else
                  Text('Price on request', style: AppTypography.subtitle),
                if (experience.isSoldOut)
                  Text(
                    'No seats left right now',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x4),
          AppButton(
            // A sold-out listing is not bookable: the server would refuse it,
            // so the button says so instead of letting the flow fail at the
            // last step.
            label: experience.isSoldOut ? 'Sold out' : AppStrings.bookNow,
            expanded: false,
            onPressed: experience.price == null || experience.isSoldOut
                ? null
                : () => context.push('/book/${experience.slug}'),
          ),
        ],
      ),
    );
  }
}
