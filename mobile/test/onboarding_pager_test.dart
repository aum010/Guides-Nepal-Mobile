import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/app/theme/app_theme.dart';
import 'package:guides_nepal/features/onboarding/onboarding_screen.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

/// Onboarding is a three-slide pager. These tests pin the two things that make
/// it usable: it says how many slides exist, and both the swipe and the dot
/// move between them.
void main() {
  Future<void> pumpOnboarding(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/sign-in',
          builder: (_, __) => const Scaffold(body: Text('sign-in-screen')),
        ),
        GoRoute(
          path: '/sign-up',
          builder: (_, __) => const Scaffold(body: Text('sign-up-screen')),
        ),
        GoRoute(
          path: '/faq',
          builder: (_, __) => const Scaffold(body: Text('faq-screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router, theme: AppTheme.light),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('first slide announces its position and both account actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOnboarding(tester);

    expect(find.text('Find your Nepal.'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Create account'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Sign in'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('swiping moves to the next slide and updates the indicator',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOnboarding(tester);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('Meet local guides.'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('Book with confidence.'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 3 of 3'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('tapping a dot jumps to that slide', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOnboarding(tester);

    await tester.tap(find.bySemanticsLabel('Page 3'));
    await tester.pumpAndSettle();

    expect(find.text('Book with confidence.'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 3 of 3'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Page 1'));
    await tester.pumpAndSettle();

    expect(find.text('Find your Nepal.'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('the account actions route to their screens', (tester) async {
    await pumpOnboarding(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('sign-up-screen'), findsOneWidget);
  });
}
