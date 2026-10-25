import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/experience.dart';
import '../experiences/experience_repository.dart';

/// The five cities verified in the platform content model.
const kCities = <String>[
  'Kathmandu',
  'Pokhara',
  'Lalitpur',
  'Bhaktapur',
  'Bharatpur',
];

/// Experience categories the public API actually serves (`GET /experiences`
/// matches these case-insensitively, so the value half must be the server's
/// own spelling — chips with unsupported values silently return nothing).
const kCategories = <(String, String)>[
  ('Cultural', 'Culture'),
  ('Food', 'Food'),
  ('Adventure', 'Adventure'),
  ('Nature', 'Outdoors'),
  ('Workshop', 'Workshops'),
];

/// Sort modes `GET /experiences` actually honours (see
/// `backend/app/api/v1/public.py`). The `null` value keeps the server's
/// default ordering, which reads as "Recommended" — an unlisted value
/// would silently fall back to it too.
const kSorts = <(String?, String)>[
  (null, 'Recommended'),
  ('price_low', 'Lowest price'),
  ('price_high', 'Highest price'),
  ('rating', 'Top rated'),
  ('popular', 'Most popular'),
];

/// Price bands mapped to the API's `min_price` / `max_price`. Open-ended
/// bands pass only one bound, so "Under $30" never caps the other side.
const kPriceBands = <(String, String, double?, double?)>[
  ('any', 'Any price', null, null),
  ('under', r'Under $30', null, 30),
  ('mid', r'$30 – $50', 30, 50),
  ('over', r'$50 & up', 50, null),
];

class ExploreFilters {
  const ExploreFilters({
    this.search = '',
    this.city,
    this.category,
    this.sort,
    this.priceBand = 'any',
  });

  final String search;
  final String? city;
  final String? category;
  final String? sort;

  /// Key into [kPriceBands] — 'any' means unfiltered.
  final String priceBand;

  /// The (min, max) bounds for [priceBand], straight from [kPriceBands].
  (double?, double?) get priceRange {
    final band = kPriceBands.firstWhere((b) => b.$1 == priceBand,
        orElse: () => kPriceBands.first);
    return (band.$3, band.$4);
  }

  ExploreFilters copyWith({
    String? search,
    String? Function()? city,
    String? Function()? category,
    String? Function()? sort,
    String? priceBand,
  }) =>
      ExploreFilters(
        search: search ?? this.search,
        city: city != null ? city() : this.city,
        category: category != null ? category() : this.category,
        sort: sort != null ? sort() : this.sort,
        priceBand: priceBand ?? this.priceBand,
      );

  bool get isEmpty =>
      search.isEmpty &&
      city == null &&
      category == null &&
      priceBand == 'any';
}

class ExploreFiltersNotifier extends StateNotifier<ExploreFilters> {
  ExploreFiltersNotifier() : super(const ExploreFilters());

  void setSearch(String value) => state = state.copyWith(search: value);
  void setCity(String? value) => state = state.copyWith(city: () => value);
  void setCategory(String? value) =>
      state = state.copyWith(category: () => value);
  void setSort(String? value) => state = state.copyWith(sort: () => value);
  void setPriceBand(String value) => state = state.copyWith(priceBand: value);

  /// Clears the filters but keeps the chosen ordering: "Clear all" answers
  /// "show me everything", not "resort it differently".
  void clear() => state = ExploreFilters(sort: state.sort);
}

final exploreFiltersProvider =
    StateNotifierProvider<ExploreFiltersNotifier, ExploreFilters>(
        (ref) => ExploreFiltersNotifier());

/// Explore results. Cancels the in-flight request whenever filters change so
/// rapid filter flips never race stale responses onto the screen. Bookings
/// are non-idempotent, but this is a read, so cancel-on-change is safe.
final exploreResultsProvider =
    FutureProvider.autoDispose<List<Experience>>((ref) async {
  final filters = ref.watch(exploreFiltersProvider);
  final token = CancelToken();
  ref.onDispose(token.cancel);
  final (minPrice, maxPrice) = filters.priceRange;

  return ref.watch(experienceRepositoryProvider).fetchExperiences(
        ExperienceQuery(
          search: filters.search.isEmpty ? null : filters.search,
          city: filters.city,
          category: filters.category,
          minPrice: minPrice,
          maxPrice: maxPrice,
          sort: filters.sort,
        ),
        cancelToken: token,
      );
});
