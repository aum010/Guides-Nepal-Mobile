import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/experience.dart';
import '../../shared/models/guide.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_repository.dart';
import '../experiences/experience_repository.dart';
import '../favorites/favorites_controller.dart';
import 'destination_data.dart';

/// One destination template driven by [Destination] data + live server
/// content (experiences and guides filtered by city).
class DestinationScreen extends ConsumerWidget {
  const DestinationScreen({super.key, required this.city});

  final String city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dest = destinationForSlug(city);
    final experiences = ref.watch(destinationExperiencesProvider(city));
    final guides = ref.watch(destinationGuidesProvider(city));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(dest.name, style: AppTypography.h3.copyWith(
                  color: AppColors.textOnPrimary)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.secondary, AppColors.primary],
                  ),
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: Icon(dest.icon,
                      size: 72,
                      color: AppColors.textOnPrimary.withValues(alpha: 0.25)),
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
                  Text(dest.tagline, style: AppTypography.overline),
                  const SizedBox(height: AppSpacing.x2),
                  Text(dest.description, style: AppTypography.body),
                  const SizedBox(height: AppSpacing.x5),
                  Text('Highlights', style: AppTypography.h3),
                  const SizedBox(height: AppSpacing.x3),
                  Wrap(
                    spacing: AppSpacing.x2,
                    runSpacing: AppSpacing.x2,
                    children: [for (final h in dest.highlights) InfoChip(label: h)],
                  ),
                ],
              ),
            ),
          ),
          // Guide-posted updates for this city sit above the shop window on
          // purpose: a closed trail or a moved pick-up changes whether a
          // traveller wants anything listed below it today.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.x4),
              child: CityUpdatesSection(city: dest.name),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter, AppSpacing.x5, AppSpacing.gutter, AppSpacing.x3),
              child: Text('Experiences in ${dest.name}',
                  style: AppTypography.h3),
            ),
          ),
          experiences.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.gutter),
                child: SkeletonList(itemCount: 3),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: ErrorStateView(
                  message:
                      e is ApiException ? e.message : AppStrings.offlineBody,
                  onRetry: () => ref
                      .invalidate(destinationExperiencesProvider(city)),
                ),
              ),
            ),
            data: (list) => list.isEmpty
                ? const SliverToBoxAdapter(
                    child: EmptyStateView(
                      icon: Icons.explore_outlined,
                      title: 'No experiences listed',
                      message: 'Guides have not published experiences here '
                          'yet. Check back soon.',
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.gutter),
                    sliver: SliverList.list(
                      children: [
                        for (final e in list) ...[
                          _experienceTile(context, ref, e),
                          const SizedBox(height: AppSpacing.x4),
                        ],
                      ],
                    ),
                  ),
          ),
          guides.when(
            loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.gutter),
                  child: SkeletonList(itemCount: 1),
                )),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (list) => list.isEmpty
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.gutter, AppSpacing.x4,
                          AppSpacing.gutter, AppSpacing.x3),
                      child: Text('Guides in ${dest.name}',
                          style: AppTypography.h3),
                    ),
                  ),
          ),
          guides.when(
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (list) => list.isEmpty
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverToBoxAdapter(
                    child: SizedBox(
                      height: 190,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.gutter),
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.x4),
                        itemBuilder: (_, i) => GuideCard(
                          guide: list[i],
                          onTap: () => context.push('/guide/${list[i].id}'),
                        ),
                      ),
                    ),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.x10)),
        ],
      ),
    );
  }

  Widget _experienceTile(BuildContext context, WidgetRef ref, Experience e) {
    final favs = ref.watch(favoritesControllerProvider);
    return ExperienceCard(
      experience: e,
      onTap: () => context.push('/experience/${e.slug}'),
      isSaved: favs.isSaved(e.slug),
      onToggleSave: () async {
        if (!ref.read(authControllerProvider).isAuthenticated) {
          context.push('/sign-in');
          return;
        }
        try {
          await ref.read(favoritesControllerProvider.notifier).toggle(e);
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

final destinationExperiencesProvider = FutureProvider.autoDispose
    .family<List<Experience>, String>((ref, city) {
  return ref
      .watch(experienceRepositoryProvider)
      .fetchExperiences(ExperienceQuery(city: city));
});

final destinationGuidesProvider = FutureProvider.autoDispose
    .family<List<Guide>, String>((ref, city) {
  return ref
      .watch(experienceRepositoryProvider)
      .fetchGuides(city: city);
});
