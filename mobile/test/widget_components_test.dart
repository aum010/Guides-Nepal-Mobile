import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/shared/models/experience.dart';
import 'package:guides_nepal/shared/models/guide.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

Experience _experience({
  String slug = 'newari-food-walk',
  String title = 'Newari Food Walk',
  double? rating = 4.8,
  int? reviewCount = 21,
  num? price = 45,
}) {
  return Experience(
    id: 7,
    slug: slug,
    title: title,
    heroImage: '', // empty URL exercises the offline placeholder — no network
    description: 'Taste your way through Patan.',
    price: price,
    duration: '3 hours',
    rating: rating,
    reviewCount: reviewCount,
    city: 'Lalitpur',
    category: 'food',
    host: const Guide(
      id: 1,
      name: 'Aarati Shrestra',
      image: '',
      role: 'Food guide',
      rating: 4.9,
      reviews: 130,
      bio: '',
      languages: ['Nepali', 'English'],
      verified: true,
      cities: ['Lalitpur'],
    ),
  );
}

void main() {
  group('ExperienceCard', () {
    testWidgets('renders title, meta, rating and per-person price',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExperienceCard(experience: _experience()),
        ),
      ));

      expect(find.text('Newari Food Walk'), findsOneWidget);
      expect(find.text('Lalitpur · 3 hours'), findsOneWidget);
      expect(find.text('4.8'), findsOneWidget);
      // Compact count in the rating row; the Semantics label still says
      // "21 reviews" for screen readers.
      expect(find.text('(21)'), findsOneWidget);
      expect(find.text(r'$45 / person'), findsOneWidget);
      // No rating → honest fallback, no fabricated stars.
      expect(find.text('New on Guides Nepal'), findsNothing);
    });

    testWidgets('shows the honest fallback when rating and price are absent',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExperienceCard(
            experience: _experience(rating: null, reviewCount: null, price: null),
          ),
        ),
      ));

      expect(find.text('New on Guides Nepal'), findsOneWidget);
      expect(find.textContaining('/ person'), findsNothing);
    });

    testWidgets('tapping the card fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExperienceCard(
            experience: _experience(),
            onTap: () => tapped = true,
          ),
        ),
      ));

      await tester.tap(find.text('Newari Food Walk'));
      expect(tapped, isTrue);
    });

    testWidgets('heart fires onToggleSave and reflects isSaved',
        (tester) async {
      var toggles = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExperienceCard(
            experience: _experience(),
            isSaved: false,
            onToggleSave: () => toggles++,
          ),
        ),
      ));

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      expect(toggles, 1);

      // Saved state swaps to the filled, tinted heart. A sub-4.7 rating is
      // used so the Guest favourite ribbon stays out of the icon query.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExperienceCard(
            experience: _experience(rating: 4.2),
            isSaved: true,
            onToggleSave: () => toggles++,
          ),
        ),
      ));
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    });

    testWidgets('exposes a screen-reader label with rating and price',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ExperienceCard(experience: _experience())),
      ));

      // Assert the label the card declares for assistive tech (node
      // partitioning can merge it upward, so read it from the widget).
      final cardSemantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(ExperienceCard),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(
        cardSemantics.properties.label,
        'Newari Food Walk, in Lalitpur, rated 4.8 out of 5 from 21 reviews, '
            r'$45 per person',
      );
      expect(cardSemantics.properties.button, isTrue);
    });
  });

  group('AppButton', () {
    testWidgets('fires onPressed when idle', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppButton(label: 'Book now', onPressed: () => taps++),
        ),
      ));

      await tester.tap(find.text('Book now'));
      expect(taps, 1);
    });

    testWidgets('loading state blocks duplicate submissions', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppButton(
            label: 'Book now',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      ));

      // Shows progress instead of the label, and swallows taps.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Book now'), findsNothing);
      await tester.tap(find.byType(CircularProgressIndicator));
      expect(taps, 0);
    });

    testWidgets('disabled button does not fire', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppButton(label: 'Continue', onPressed: null),
        ),
      ));
      await tester.tap(find.text('Continue'));
      expect(taps, 0);
    });
  });

  group('EmptyStateView / ErrorStateView', () {
    testWidgets('empty state action fires', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmptyStateView(
            title: 'Nothing saved yet',
            message: 'Tap the heart to save.',
            actionLabel: 'Explore experiences',
            onAction: () => taps++,
          ),
        ),
      ));

      expect(find.text('Nothing saved yet'), findsOneWidget);
      await tester.tap(find.text('Explore experiences'));
      expect(taps, 1);
    });

    testWidgets('error state retry fires with friendly copy only',
        (tester) async {
      var retries = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ErrorStateView(
            message: 'Could not reach Guides Nepal. Check your connection.',
            onRetry: () => retries++,
          ),
        ),
      ));

      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // No backend trace leaked into the message.
      expect(find.textContaining('Exception'), findsNothing);
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });
  });

  group('AppFilterChip', () {
    testWidgets('reports taps and renders selected state', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppFilterChip(
            label: 'Pokhara',
            selected: false,
            onTap: () => taps++,
          ),
        ),
      ));

      expect(find.text('Pokhara'), findsOneWidget);
      await tester.tap(find.text('Pokhara'));
      expect(taps, 1);
    });
  });
}
