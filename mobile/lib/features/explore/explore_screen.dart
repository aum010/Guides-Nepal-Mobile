import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/debouncer.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/experience.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_repository.dart';
import '../favorites/favorites_controller.dart';
import 'explore_controller.dart';

/// Category → glyph. Icons make the category chips read as a different kind
/// of filter than the city chips sharing the same row.
const _categoryIcons = <String, IconData>{
  'Cultural': Icons.temple_buddhist_outlined,
  'Food': Icons.restaurant_outlined,
  'Adventure': Icons.hiking_rounded,
  'Nature': Icons.forest_outlined,
  'Workshop': Icons.palette_outlined,
};

/// Explore tab: debounced search plus city and category filters, backed by
/// the verified `GET /experiences` endpoint.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  final _debouncer = Debouncer();

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(exploreFiltersProvider).search;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debouncer.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debouncer.run(
      () => ref.read(exploreFiltersProvider.notifier).setSearch(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(exploreFiltersProvider);
    final results = ref.watch(exploreResultsProvider);
    final favorites = ref.watch(favoritesControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenHeader(
              title: AppStrings.exploreTitle,
              subtitle: results.maybeWhen(
                data: (list) => _resultSummary(list.length, filters.city),
                orElse: () => AppStrings.exploreSubline,
              ),
              trailing: _SortButton(sort: filters.sort),
            ),
            const SizedBox(height: AppSpacing.x4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                style: AppTypography.body,
                decoration: InputDecoration(
                  hintText: AppStrings.searchHint,
                  filled: true,
                  fillColor: AppColors.surface,
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textSecondary),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            ref
                                .read(exploreFiltersProvider.notifier)
                                .setSearch('');
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.x3,
                    horizontal: AppSpacing.x4,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
                    borderSide: const BorderSide(
                        color: AppColors.secondary, width: 1.6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            _FilterBar(filters: filters),
            Expanded(
              child: results.when(
                loading: () => const SkeletonList(itemCount: 4),
                error: (e, _) => ErrorStateView(
                  message: e is ApiException
                      ? e.message
                      : AppStrings.offlineBody,
                  onRetry: () =>
                      ref.invalidate(exploreResultsProvider),
                ),
                data: (list) => list.isEmpty
                    ? EmptyStateView(
                        icon: Icons.search_off,
                        title: AppStrings.noExperiencesTitle,
                        message: AppStrings.noExperiencesBody,
                        actionLabel: 'Clear filters',
                        onAction: () =>
                            ref.read(exploreFiltersProvider.notifier).clear(),
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(exploreResultsProvider),
                        child: GridView.builder(
                          padding: const EdgeInsets.all(AppSpacing.gutter),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: AppSpacing.x6,
                            crossAxisSpacing: AppSpacing.x4,
                            childAspectRatio: 0.68,
                          ),
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final e = list[index];
                            return ExperienceCard(
                              experience: e,
                              imageHeight: 146,
                              isSaved: favorites.isSaved(e.slug, experienceId: e.id),
                              onTap: () =>
                                  context.push('/experience/${e.slug}'),
                              onToggleSave: () => _toggleSave(e),
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

/// "12 experiences · Kathmandu" — the count is the subtitle, so the header
  /// carries the result context instead of a floating caption line.
  String _resultSummary(int count, String? city) {
    final noun = count == 1 ? '1 experience' : '$count experiences';
    // "in Nepal" not "across Nepal": the shorter phrase holds one line beside
    // the sort control, where the longer one orphaned the country on its own.
    if (city == null || city.isEmpty) return '$noun in Nepal';
    return '$noun in $city';
  }

  Future<void> _toggleSave(Experience e) async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthenticated) {
      context.push('/sign-in');
      return;
    }
    try {
      await ref.read(favoritesControllerProvider.notifier).toggle(e);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update saved list.')),
        );
      }
    }
  }
}

/// Sort control in the shared header slot: shows the active ordering and
/// opens a sheet with every mode the server supports. Placed apart from the
/// filter chips because ordering answers "in what order", not "what".
class _SortButton extends ConsumerWidget {
  const _SortButton({required this.sort});

  final String? sort;

  String get _label =>
      kSorts.firstWhere((s) => s.$1 == sort, orElse: () => kSorts.first).$2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = sort != null;
    return Semantics(
      button: true,
      label: '${AppStrings.sortBy}: $_label',
      child: Material(
        color: isActive ? AppColors.primary : AppColors.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: InkWell(
          onTap: () => _showSheet(context, ref),
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x3,
              vertical: AppSpacing.x2 + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.swap_vert_rounded,
                  size: 16,
                  color: isActive
                      ? AppColors.textOnPrimary
                      : AppColors.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _label,
                  style: AppTypography.small.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isActive
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

  Future<void> _showSheet(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(exploreFiltersProvider.notifier);
    // Picking "Recommended" also means a null sort, so the sheet returns a
    // record: a null result then always means "dismissed, change nothing".
    final picked = await showModalBottomSheet<({String? sort})>(
      context: context,
      // Pushed on the root navigator: branch-navigator sheets render
      // beneath the floating nav bar, so its scrim and body must rise
      // above the shell route to cover it.
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter,
                  AppSpacing.x5, AppSpacing.gutter, AppSpacing.x2),
              child: Text(AppStrings.sortBy, style: AppTypography.h3),
            ),
            for (final (value, label) in kSorts)
              ListTile(
                dense: true,
                title: Text(label, style: AppTypography.body),
                trailing: value == sort
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.secondary, size: 20)
                    : null,
                onTap: () => Navigator.of(ctx).pop((sort: value)),
              ),
            const SizedBox(height: AppSpacing.x3),
          ],
        ),
      ),
    );
    if (picked != null) controller.setSort(picked.sort);
  }
}

/// Band picker shared with the sort sheet: title, one row per band, check
/// on the active one. Popping a record keeps dismissal (no row tapped)
/// distinct from any band value.
Future<void> _showPriceSheet(
    BuildContext context, WidgetRef ref, String current) async {
  final controller = ref.read(exploreFiltersProvider.notifier);
  final picked = await showModalBottomSheet<({String band})>(
    context: context,
    // Root navigator so the sheet's scrim covers the floating nav bar too
    // (sheets default to the branch navigator, which renders under the bar).
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusXl),
      ),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter,
                AppSpacing.x5, AppSpacing.gutter, AppSpacing.x2),
            child: Text(AppStrings.priceRange, style: AppTypography.h3),
          ),
          for (final (value, label, _, _) in kPriceBands)
            ListTile(
              dense: true,
              title: Text(label, style: AppTypography.body),
              trailing: value == current
                  ? const Icon(Icons.check_rounded,
                      color: AppColors.secondary, size: 20)
                  : null,
              onTap: () => Navigator.of(ctx).pop((band: value)),
            ),
          const SizedBox(height: AppSpacing.x3),
        ],
      ),
    ),
  );
  if (picked != null) controller.setPriceBand(picked.band);
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filters});

  final ExploreFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(exploreFiltersProvider.notifier);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        children: [
          AppFilterChip(
            label: 'All cities',
            selected: filters.city == null &&
                filters.category == null &&
                filters.priceBand == 'any',
            onTap: controller.clear,
          ),
          const SizedBox(width: AppSpacing.x2),
          // Price sits beside the reset chip so it stays visible at the
          // start of the row on a phone-width screen instead of hiding
          // behind every city and category chip.
          AppFilterChip(
            label: filters.priceBand == 'any'
                ? AppStrings.priceRange
                : kPriceBands
                    .firstWhere((b) => b.$1 == filters.priceBand)
                    .$2,
            icon: Icons.payments_outlined,
            selected: filters.priceBand != 'any',
            onTap: () => _showPriceSheet(context, ref, filters.priceBand),
          ),
          const SizedBox(width: AppSpacing.x2),
          // A hairline separates "how much" from "where".
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.only(right: AppSpacing.x2),
            color: AppColors.border,
          ),
          for (final city in kCities) ...[
            AppFilterChip(
              label: city,
              selected: filters.city == city,
              onTap: () => controller.setCity(filters.city == city ? null : city),
            ),
            const SizedBox(width: AppSpacing.x2),
          ],
          // A hairline separates "where" from "what": the two groups share
          // the pill shape but answer different questions.
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.only(right: AppSpacing.x2),
            color: AppColors.border,
          ),
          for (final (value, label) in kCategories) ...[
            AppFilterChip(
              label: label,
              icon: _categoryIcons[value],
              selected: filters.category == value,
              onTap: () => controller
                  .setCategory(filters.category == value ? null : value),
            ),
            const SizedBox(width: AppSpacing.x2),
          ],
          if (!filters.isEmpty) ...[
            const SizedBox(width: AppSpacing.x1),
            TextButton(
              onPressed: controller.clear,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondary,
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(44, AppSpacing.minTouchTarget),
              ),
              child: Text(AppStrings.clearFilters,
                  style: AppTypography.label
                      .copyWith(color: AppColors.secondary)),
            ),
          ],
        ],
      ),
    );
  }
}
