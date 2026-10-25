import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/app_user.dart';
import '../../shared/models/experience.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_repository.dart';
import '../destinations/destination_data.dart';
import '../experiences/experience_repository.dart';
import '../explore/explore_controller.dart' show kCities;
import '../favorites/favorites_controller.dart';
import 'home_city_store.dart';

/// Home data: one experiences fetch drives hero, categories and rails.
final homeExperiencesProvider =
    FutureProvider.autoDispose<List<Experience>>((ref) {
  return ref
      .watch(experienceRepositoryProvider)
      .fetchExperiences(const ExperienceQuery());
});

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final experiences = ref.watch(homeExperiencesProvider);
    final guides = ref.watch(guidesProvider);
    final homeCity = ref.watch(homeCityProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(homeExperiencesProvider);
            ref.invalidate(guidesProvider);
            ref.invalidate(cityUpdatesProvider(ref.read(homeCityProvider)));
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(context, auth.user)),
              SliverToBoxAdapter(child: _searchBar(context)),
              SliverToBoxAdapter(child: _hero(context)),
              SliverToBoxAdapter(child: _localUpdatesHeader(ref, homeCity)),
              // CityUpdatesSection is a box widget in every state (shrink,
              // error row, card column) — the scroll view needs slivers, so
              // it must be adapted here or RenderViewport rejects the child.
              SliverToBoxAdapter(
                child: CityUpdatesSection(city: homeCity, title: null),
              ),
              SliverToBoxAdapter(
                child: _sectionTitle(context, 'Explore destinations',
                    onSeeAll: () => context.go('/explore')),
              ),
              SliverToBoxAdapter(child: _destinationRail(context)),
              SliverToBoxAdapter(
                child: _sectionTitle(context, 'Experiences for you',
                    onSeeAll: () => context.go('/explore')),
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
                      message: e is ApiException
                          ? e.message
                          : AppStrings.offlineBody,
                      onRetry: () =>
                          ref.invalidate(homeExperiencesProvider),
                    ),
                  ),
                ),
                data: (list) => SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.gutter),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: AppSpacing.x6,
                      crossAxisSpacing: AppSpacing.x4,
                      childAspectRatio: 0.68,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _experienceTile(
                          context, ref, list[index],
                          imageHeight: 146),
                      childCount: list.length < 6 ? list.length : 6,
                    ),
                  ),
                ),
              ),
              guides.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.gutter),
                    child: SkeletonList(itemCount: 2),
                  ),
                ),
                error: (_, __) => const SliverToBoxAdapter(
                    child: SizedBox.shrink()),
                data: (list) => list.isEmpty
                    ? const SliverToBoxAdapter(child: SizedBox.shrink())
                    : SliverToBoxAdapter(
                        child: _sectionTitle(context, 'Local guides to meet'),
                      ),
              ),
              guides.when(
                loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
                data: (list) => list.isEmpty
                    ? const SliverToBoxAdapter(child: SizedBox.shrink())
                    : SliverToBoxAdapter(
                        child: SizedBox(
                          height: 216,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.gutter),
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: AppSpacing.x3),
                            itemBuilder: (_, i) => GuideCard(
                              guide: list[i],
                              onTap: () =>
                                  context.push('/guide/${list[i].id}'),
                            ),
                          ),
                        ),
                      ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.x8)),
            ],
          ),
        ),
      ),
    );
  }

  /// Greeting block with quick entries to the AI companion and the
  /// traveller's own profile. The salutation keeps the subline copy stable
  /// for tests and screen readers.
  Widget _header(BuildContext context, AppUser? user) {
    final name = user?.firstName ?? 'traveler';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, AppSpacing.x4, AppSpacing.gutter, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Namaste, $name',
                  style: AppTypography.h2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(AppStrings.homeSubline,
                    style: AppTypography.body
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
          _HeaderIconButton(
            tooltip: AppStrings.mailaDai,
            icon: Icons.auto_awesome_rounded,
            onTap: () => context.push('/ai'),
          ),
          const SizedBox(width: AppSpacing.x2),
          _ProfileButton(user: user),
        ],
      ),
    );
  }

  /// "Updates in Kathmandu" header with a city picker. Deliberately lives
  /// outside [CityUpdatesSection] so it stays on screen even when the feed
  /// is empty or still loading — Home is where a traveller checks their
  /// city, whether or not a guide has posted anything.
  Widget _localUpdatesHeader(WidgetRef ref, String homeCity) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, AppSpacing.x6, AppSpacing.gutter, AppSpacing.x3),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    AppStrings.localUpdates,
                    style: AppTypography.h3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                // Live count of this city's updates, read straight from the
                // provider the feed below renders — no extra fetch, so the
                // badge always agrees with the list beneath it. Nothing to
                // show while loading, on error, or when there are none.
                ref.watch(cityUpdatesProvider(homeCity)).when(
                      loading: () => const SizedBox.shrink(),
                      error: (Object _, Object __) => const SizedBox.shrink(),
                      data: (list) => list.isEmpty
                          ? const SizedBox.shrink()
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.x2 + 2, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfacePeach,
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusPill),
                              ),
                              child: Text(
                                '${list.length}',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Change city, currently $homeCity',
            child: GestureDetector(
              onTap: () => _pickCity(ref, homeCity),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x3,
                  vertical: AppSpacing.x1 + 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 14, color: AppColors.secondary),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 92),
                      child: Text(
                        homeCity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.label
                            .copyWith(color: AppColors.secondary),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.expand_more,
                        size: 16, color: AppColors.secondary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCity(WidgetRef ref, String current) async {
    final selected = await showModalBottomSheet<String>(
      context: ref.context,
      // Root navigator so the picker covers the floating nav bar.
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final city in kCities)
                ListTile(
                  title: Text(city),
                  trailing: city == current
                      ? const Icon(Icons.check, color: AppColors.secondary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(city),
                ),
            ],
          ),
        ),
    );
    if (selected != null) {
      await ref.read(homeCityProvider.notifier).setCity(selected);
    }
  }

  /// Airbnb-style search pill: a solid brand icon leads the action and a
  /// filter glyph closes it, framing the hint between them. Tapping the
  /// whole pill lands on Explore with the field focused.
  Widget _searchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.x4,
          AppSpacing.gutter, AppSpacing.x2),
      child: Semantics(
        button: true,
        label: 'Search ${AppStrings.searchHint.toLowerCase()}',
        child: GestureDetector(
          onTap: () => context.go('/explore'),
          child: Container(
            height: 56,
            padding: const EdgeInsets.all(AppSpacing.x1 + 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.search_rounded,
                      color: AppColors.textOnPrimary, size: 21),
                ),
                const SizedBox(width: AppSpacing.x3),
                // Constrained so long hint text ellipsizes instead of
                // overflowing the pill on narrow screens.
                Expanded(
                  child: Text(
                    AppStrings.searchHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.surfacePeach,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.tune_rounded,
                      color: AppColors.secondary, size: 19),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Brand hero: gradient plate with soft decorative light, a glass
  /// eyebrow chip and the platform promise in the editorial display face.
  Widget _hero(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
        child: Stack(
          children: [
            // minHeight instead of a fixed height: the headline/subline/button
            // column must be able to grow (text scaling, narrow widths) rather
            // than overflow its box with a yellow-stripe error.
            Container(
              constraints: const BoxConstraints(minHeight: 208),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.secondary, AppColors.primary],
                ),
              ),
              padding: const EdgeInsets.all(AppSpacing.x6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x2 + 4, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                    ),
                    child: Text(
                      'LOCAL GUIDES · NEPAL',
                      style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Text(
                    AppStrings.heroHeadline,
                    style: AppTypography.displaySmall
                        .copyWith(color: AppColors.textOnPrimary),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    AppStrings.heroSubline,
                    style: AppTypography.small.copyWith(
                        color: AppColors.textOnPrimary
                            .withValues(alpha: 0.85)),
                  ),
                  const SizedBox(height: AppSpacing.x5),
                  AppButton(
                    label: AppStrings.exploreExperiences,
                    expanded: false,
                    onPressed: () => context.go('/explore'),
                  ),
                ],
              ),
            ),
            Positioned(
              top: -34,
              right: -30,
              child: _HeroOrbit(
                size: 150,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
            Positioned(
              bottom: -52,
              left: -30,
              child: _HeroOrbit(
                size: 130,
                color: AppColors.accent.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, AppSpacing.x6, AppSpacing.gutter, AppSpacing.x3),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppTypography.h3),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.x1, horizontal: AppSpacing.x1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(AppStrings.seeAll,
                        style: AppTypography.label
                            .copyWith(color: AppColors.secondary)),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 12, color: AppColors.secondary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Destination tiles as gradient plates — city color identity without
  /// fabricating photography the platform does not ship.
  Widget _destinationRail(BuildContext context) {
    return SizedBox(
      height: 156,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        itemCount: kDestinations.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.x3),
        itemBuilder: (_, i) {
          final dest = kDestinations[i];
          return Semantics(
            button: true,
            label: '${dest.name}, ${dest.tagline}',
            child: GestureDetector(
              onTap: () => context.push('/destination/${dest.slug}'),
              child: Container(
                width: 136,
                padding: const EdgeInsets.all(AppSpacing.x3 + 2),
                decoration: BoxDecoration(
                  gradient: dest.gradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  boxShadow: AppShadows.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(dest.icon,
                          size: 20, color: AppColors.textOnPrimary),
                    ),
                    const Spacer(),
                    Text(
                      dest.name,
                      style: AppTypography.subtitle.copyWith(
                        color: AppColors.textOnPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dest.tagline,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _experienceTile(
    BuildContext context,
    WidgetRef ref,
    Experience e, {
    double? imageHeight,
  }) {
    final favs = ref.watch(favoritesControllerProvider);
    return ExperienceCard(
      experience: e,
      imageHeight: imageHeight,
      onTap: () => context.push('/experience/${e.slug}'),
      isSaved: favs.isSaved(e.slug),
      onToggleSave: () async {
        final auth = ref.read(authControllerProvider);
        if (!auth.isAuthenticated) {
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

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            child: Icon(icon, size: 22, color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

/// Signed-in travellers see their initials (or avatar when the profile has
/// one); everyone else gets a neutral profile glyph. Tapping opens Profile.
class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user?.avatarUrl;
    return Tooltip(
      message: AppStrings.navProfile,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/profile'),
          child: SizedBox(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            child: avatarUrl != null && avatarUrl.isNotEmpty
                ? NetworkImageView(
                    url: avatarUrl,
                    semanticsLabel: AppStrings.navProfile,
                  )
                : user != null
                    ? Center(
                        child: Text(
                          user!.initials,
                          style: AppTypography.label.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : const Icon(Icons.person_outline_rounded,
                        size: 22, color: AppColors.secondary),
          ),
        ),
      ),
    );
  }
}

class _HeroOrbit extends StatelessWidget {
  const _HeroOrbit({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
