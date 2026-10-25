import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/features/experiences/experience_repository.dart';
import 'package:guides_nepal/features/explore/explore_controller.dart';

void main() {
  test('sort modes match what the experiences API accepts', () {
    // Unknown values fall back to the server default, so every offered
    // mode must be one the backend actually handles.
    const supported = {'price_low', 'price_high', 'rating', 'popular'};
    for (final (value, label) in kSorts) {
      if (value != null) {
        expect(supported.contains(value), isTrue,
            reason: '"$label" is not a supported sort value');
      }
    }
    expect(kSorts.first.$1, isNull, reason: 'default ordering is Recommended');
  });

  test('filters carry sort through copy and clear', () {
    final notifier = ExploreFiltersNotifier();
    notifier.setCity('Kathmandu');
    notifier.setSort('rating');
    expect(notifier.state.sort, 'rating');
    expect(notifier.state.city, 'Kathmandu');

    // Clearing filters keeps the chosen ordering.
    notifier.clear();
    expect(notifier.state.city, isNull);
    expect(notifier.state.sort, 'rating');

    notifier.setSort(null);
    expect(notifier.state.sort, isNull);
  });

  test('sort is serialised as the sort query parameter', () {
    const query = ExperienceQuery(sort: 'price_low');
    expect(query.toParams()['sort'], 'price_low');

    const unsorted = ExperienceQuery(city: 'Pokhara');
    expect(unsorted.toParams().containsKey('sort'), isFalse);
  });

  test('price bands map to half-open API bounds', () {
    final notifier = ExploreFiltersNotifier();

    // Every band key resolves to bounds and 'any' passes neither.
    for (final (key, _, _, _) in kPriceBands) {
      notifier.setPriceBand(key);
      final (minPrice, maxPrice) = notifier.state.priceRange;
      expect(minPrice, kPriceBands.firstWhere((b) => b.$1 == key).$3);
      expect(maxPrice, kPriceBands.firstWhere((b) => b.$1 == key).$4);
    }
    expect(const ExploreFilters().priceRange, (null, null));

    // Open-ended bands send only one bound, never a fabricated cap.
    notifier.setPriceBand('under');
    final under = ExperienceQuery(
      minPrice: notifier.state.priceRange.$1,
      maxPrice: notifier.state.priceRange.$2,
    );
    expect(under.toParams()['max_price'], 30);
    expect(under.toParams().containsKey('min_price'), isFalse);

    notifier.setPriceBand('over');
    final over = ExperienceQuery(
      minPrice: notifier.state.priceRange.$1,
      maxPrice: notifier.state.priceRange.$2,
    );
    expect(over.toParams()['min_price'], 50);
    expect(over.toParams().containsKey('max_price'), isFalse);

    // An active band counts as a filter for the "Clear all" affordance.
    expect(notifier.state.isEmpty, isFalse);
    notifier.clear();
    expect(notifier.state.priceBand, 'any');
    expect(notifier.state.isEmpty, isTrue);
  });
}
