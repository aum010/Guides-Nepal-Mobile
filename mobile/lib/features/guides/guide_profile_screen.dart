import 'package:flutter/material.dart';
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
import '../../shared/widgets/widgets.dart';
import '../auth/auth_repository.dart';
import '../experiences/experience_repository.dart';
import '../favorites/favorites_controller.dart';

/// A guide, resolved via the verified `GET /api/v1/guides/{id}` endpoint.
final guideProvider = FutureProvider.autoDispose.family<Guide, int>(
  (ref, id) => ref.watch(experienceRepositoryProvider).fetchGuide(id),
);

/// Experiences tied to this guide's cities (used to seed the profile rail).
final guideExperiencesProvider = FutureProvider.autoDispose
    .family<List<Experience>, List<String>>((ref, cities) async {
  final repo = ref.watch(experienceRepositoryProvider);
  final all = <Experience>[];
  for (final city in cities) {
    final batch = await repo.fetchExperiences(ExperienceQuery(city: city));
    all.addAll(batch);
  }
  return all;
});

class GuideProfileScreen extends ConsumerWidget {
  const GuideProfileScreen({super.key, required this.guideId});

  final int guideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guideAsync = ref.watch(guideProvider(guideId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: guideAsync.when(
        loading: () => const SafeArea(child: _GuideSkeleton()),
        error: (e, _) => SafeArea(
          child: ErrorStateView(
            message: e is ApiException ? e.message : AppStrings.offlineBody,
            onRetry: () => ref.invalidate(guideProvider(guideId)),
          ),
        ),
        data: (guide) => _GuideBody(guide: guide),
      ),
    );
  }
}

class _GuideSkeleton extends StatelessWidget {
  const _GuideSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(height: 200, radius: 0),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 180, height: 24),
              const SizedBox(height: AppSpacing.x3),
              const SkeletonBox(width: 240, height: 14),
              const SizedBox(height: AppSpacing.x5),
              const SkeletonBox(height: 100),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuideBody extends ConsumerWidget {
  const _GuideBody({required this.guide});

  final Guide guide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final experiences = guide.cities.isEmpty
        ? const AsyncValue<List<Experience>>.data(<Experience>[])
        : ref.watch(guideExperiencesProvider(guide.cities));

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          flexibleSpace: FlexibleSpaceBar(
            background: guide.image.isNotEmpty
                ? NetworkImageView(url: guide.image, semanticsLabel: guide.name)
                : Container(
                    color: AppColors.primary,
                    child: const Center(
                      child: Icon(Icons.person_outline,
                          size: 64, color: AppColors.tertiary),
                    ),
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(guide.name, style: AppTypography.h1),
                    ),
                    if (guide.verified)
                      InfoChip(icon: Icons.verified_outlined,
                          label: 'Verified'),
                  ],
                ),
                if (guide.role.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x1),
                  Text(guide.role, style: AppTypography.subtitle
                      .copyWith(color: AppColors.secondary)),
                ],
                const SizedBox(height: AppSpacing.x3),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 18, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text(guide.rating.toStringAsFixed(1),
                        style: AppTypography.bodyMedium),
                    const SizedBox(width: 6),
                    Text('(${Formatters.reviewCount(guide.reviews)})',
                        style: AppTypography.caption),
                  ],
                ),
                if (guide.bio.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x5),
                  Text('About', style: AppTypography.h3),
                  const SizedBox(height: AppSpacing.x2),
                  Text(guide.bio,
                      style: AppTypography.body
                          .copyWith(color: AppColors.textSecondary)),
                ],
                if (guide.cities.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x5),
                  Text('Where they guide', style: AppTypography.h3),
                  const SizedBox(height: AppSpacing.x3),
                  Wrap(
                    spacing: AppSpacing.x2,
                    runSpacing: AppSpacing.x2,
                    children: [for (final c in guide.cities) InfoChip(label: c)],
                  ),
                ],
                if (guide.languages.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x5),
                  Text('Languages', style: AppTypography.h3),
                  const SizedBox(height: AppSpacing.x3),
                  Wrap(
                    spacing: AppSpacing.x2,
                    runSpacing: AppSpacing.x2,
                    children: [
                      for (final l in guide.languages)
                        InfoChip(icon: Icons.translate_outlined, label: l),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.x6),
                Text('Experiences', style: AppTypography.h3),
                const SizedBox(height: AppSpacing.x3),
              ],
            ),
          ),
        ),
        experiences.when(
          loading: () => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              child: SkeletonList(itemCount: 2),
            ),
          ),
          error: (_, __) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              child: Text('Experiences are unavailable right now.',
                  style: AppTypography.caption),
            ),
          ),
          data: (list) => list.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.gutter),
                    child: EmptyStateView(
                      icon: Icons.explore_outlined,
                      title: 'No experiences yet',
                      message: 'This guide has not published experiences '
                          'that we can show here.',
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.gutter),
                  sliver: SliverList.list(
                    children: [
                      for (final e in list.take(8)) ...[
                        _GuideExperienceTile(experience: e),
                        const SizedBox(height: AppSpacing.x4),
                      ],
                    ],
                  ),
                ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.x10)),
      ],
    );
  }
}

class _GuideExperienceTile extends ConsumerWidget {
  const _GuideExperienceTile({required this.experience});

  final Experience experience;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoritesControllerProvider);
    return ExperienceCard(
      experience: experience,
      onTap: () => context.push('/experience/${experience.slug}'),
      isSaved: favs.isSaved(experience.slug),
      onToggleSave: () async {
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
      },
    );
  }
}
