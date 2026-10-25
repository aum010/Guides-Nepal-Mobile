import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/app/theme/app_theme.dart';
import 'package:guides_nepal/features/explore/explore_controller.dart';
import 'package:guides_nepal/features/explore/explore_screen.dart';

void main() {
  testWidgets('price chip opens the band sheet and applies a selection',
      (tester) async {
    // Wide surface so the whole chip row (cities, categories, price) is on
    // screen without scrolling — test fonts render glyphs as wide squares,
    // so the row needs much more room than it does on a real device.
    tester.view.physicalSize = const Size(2600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ExploreScreen()),
        ),
      ),
    );
    // Let the initial results future settle (it fails offline in tests,
    // which renders the error state — the filter row still exists). The
    // loading skeleton animates forever, so pump a fixed duration instead
    // of settling.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Price range'), findsOneWidget);

    await tester.tap(find.text('Price range'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // The sheet lists every band with the active one checked.
    expect(find.text('Any price'), findsWidgets);
    expect(find.text('Under \$30'), findsOneWidget);
    expect(find.text('\$30 – \$50'), findsOneWidget);
    expect(find.text('\$50 & up'), findsOneWidget);

    await tester.tap(find.text('Under \$30'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // The chip now reads as the active band and the state carries it.
    expect(find.text('Under \$30'), findsWidgets);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ExploreScreen)),
      listen: false,
    );
    expect(container.read(exploreFiltersProvider).priceBand, 'under');
    expect(container.read(exploreFiltersProvider).priceRange, (null, 30.0));

    // Clear-all becomes available once the band counts as a filter.
    expect(find.text('Clear all'), findsOneWidget);
  });
}
