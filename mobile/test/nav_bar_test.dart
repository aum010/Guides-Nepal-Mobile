import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/app/router/app_router.dart';
import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/features/auth/auth_controller.dart';
import 'package:guides_nepal/l10n/app_strings.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

class _FakeAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.authenticated);
}

final _booking = <String, dynamic>{
  'id': 1,
  'experience_id': 7,
  'experience_title': 'Sunrise over Sarangkot',
  'city': 'Pokhara',
  'date': '2026-11-02T00:00:00Z',
  'guests': 2,
  'price': 200,
  'status': 'upcoming',
  'user_id': 11,
  'created_at': '2026-10-21T09:00:00Z',
  'image': null,
};

/// Answers whatever the shell's branches fetch; one upcoming trip so the
/// Trips tab has a real confirmation dialog to open.
class _FakeShellApi extends ApiClient {
  final List<String> postedPaths = [];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    switch (path) {
      case '/bookings/':
        return _ok([_booking]);
      case '/profile/me':
        return _ok({
          'id': 11,
          'email': 'traveler@example.com',
          'role': 'traveler',
        });
      default:
        // experiences, guides, updates, bookmarks — all list endpoints.
        return _ok(<dynamic>[]);
    }
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    postedPaths.add(path);
    return _ok(<dynamic>{});
  }

  Response<dynamic> _ok(Object data) => Response(
        data: data,
        requestOptions: RequestOptions(path: '/'),
      );
}

/// Coverage for the redesigned floating nav: where the active icon lives,
/// how taps report, and — against the real [appRouterProvider] shell —
/// that traveler modals are pushed on the root navigator so they cover
/// the bar instead of hiding beneath it.
void main() {
  // Same five destinations the app shell wires up.
  const items = [
    FloatingNavItem(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
      label: AppStrings.navHome,
    ),
    FloatingNavItem(
      icon: Icons.search_outlined,
      selectedIcon: Icons.search_rounded,
      label: AppStrings.navExplore,
    ),
    FloatingNavItem(
      icon: Icons.card_travel_outlined,
      selectedIcon: Icons.card_travel_rounded,
      label: AppStrings.navTrips,
    ),
    FloatingNavItem(
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
      label: AppStrings.navInbox,
    ),
    FloatingNavItem(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: AppStrings.navProfile,
    ),
  ];

  Future<void> pumpNav(
    WidgetTester tester, {
    required int selectedIndex,
    required ValueChanged<int> onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: FloatingNavBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onTap,
            items: items,
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('raised badge', () {
    testWidgets('holds the active icon; the slot keeps only its label',
        (tester) async {
      await pumpNav(tester, selectedIndex: 0, onTap: (_) {});

      // The selected glyph exists exactly once — inside the badge — while
      // its slot's outlined twin is hidden so labels stay on one baseline.
      expect(find.byIcon(Icons.explore), findsOneWidget);
      expect(find.byIcon(Icons.explore_outlined), findsNothing);
      // Inactive slots keep their outlined icon in the bar.
      expect(find.byIcon(Icons.card_travel_outlined), findsOneWidget);
      for (final label in const [
        AppStrings.navHome,
        AppStrings.navExplore,
        AppStrings.navTrips,
        AppStrings.navInbox,
        AppStrings.navProfile,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('tapping a slot reports its index and moves the badge',
        (tester) async {
      final taps = <int>[];
      await pumpNav(
        tester,
        selectedIndex: 0,
        onTap: taps.add,
      );

      await tester.tap(find.text(AppStrings.navTrips));
      await tester.pumpAndSettle();
      expect(taps, [2]);

      // The shell would now drive selectedIndex: 2 — the badge (and its
      // notch) glide to Trips and the old slot reverts to its idle icon.
      await pumpNav(tester, selectedIndex: 2, onTap: taps.add);
      expect(find.byIcon(Icons.card_travel_rounded), findsOneWidget);
      expect(find.byIcon(Icons.card_travel_outlined), findsNothing);
      expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
      expect(find.byIcon(Icons.explore), findsNothing);
    });
  });

  group('modal stacking', () {
    late _FakeShellApi fake;

    Future<GoRouter> pumpShell(WidgetTester tester) async {
      fake = _FakeShellApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(fake),
            authControllerProvider.overrideWith(_FakeAuthController.new),
          ],
          child: Consumer(
            builder: (context, ref, _) =>
                MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(MaterialApp));
      return ProviderScope.containerOf(element).read(appRouterProvider);
    }

    /// Taps the Profile slot of the nav bar — wherever it sits on screen —
    /// the way a user would while a modal is up.
    Future<void> tapProfileSlot(WidgetTester tester) async {
      final rect = tester.getRect(find.byType(FloatingNavBar));
      await tester.tapAt(
        Offset(rect.left + rect.width * 0.9, rect.center.dy),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'a confirmation dialog covers the nav bar instead of sitting under it',
        (tester) async {
      final router = await pumpShell(tester);
      router.go('/trips');
      await tester.pumpAndSettle();
      expect(find.text('Sunrise over Sarangkot'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Cancel trip'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this trip?'), findsOneWidget);

      await tapProfileSlot(tester);

      // The barrier absorbed the tap: the dialog dismissed, no request was
      // sent, and Trips is still the onstage branch. Had the nav bar sat
      // on top, the tap would have switched branches and dragged the
      // dialog offstage with its branch.
      expect(find.text('Cancel this trip?'), findsNothing);
      expect(find.text('Sunrise over Sarangkot'), findsOneWidget);
      expect(fake.postedPaths, isEmpty);
    });

    testWidgets('a bottom sheet rises over the nav bar', (tester) async {
      final router = await pumpShell(tester);
      router.go('/explore');
      await tester.pumpAndSettle();
      expect(find.text('Price range'), findsOneWidget);

      await tester.tap(find.text('Price range'));
      await tester.pumpAndSettle();
      // The band list proves the sheet opened on the root navigator.
      expect(find.text(r'Under $30'), findsOneWidget);

      await tapProfileSlot(tester);

      // Barrier dismissed the sheet; Explore is still the active branch
      // (its price chip is back, exactly once — the sheet's copy is gone).
      expect(find.text(r'Under $30'), findsNothing);
      expect(find.text('Price range'), findsOneWidget);
    });

    testWidgets('the city picker sheet rises over the nav bar',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpShell(tester); // starts on Home

      final chip = find.bySemanticsLabel(RegExp('Change city'));
      expect(chip, findsOneWidget);

      await tester.tap(chip);
      await tester.pumpAndSettle();
      // The sheet lists every platform city — proof it opened.
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Bharatpur'), findsOneWidget);

      await tapProfileSlot(tester);

      // Barrier absorbed the tap: the sheet dismissed and Home is still
      // the active branch (its city chip still resolves).
      expect(find.byType(BottomSheet), findsNothing);
      expect(chip, findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the sign-out dialog covers the nav bar', (tester) async {
      // A tall surface puts the whole account section on screen, so the
      // below-the-fold buttons are tappable without scrolling.
      tester.view.physicalSize = const Size(2400, 7200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final router = await pumpShell(tester);
      router.go('/profile');
      await tester.pumpAndSettle();

      final button = find.widgetWithText(AppButton, AppStrings.signOut);
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Are you sure you want to sign out?'), findsOneWidget);

      await tapProfileSlot(tester);

      // The barrier swallowed the tap: no sign-out request was sent and
      // Profile is still the active branch.
      expect(find.text('Are you sure you want to sign out?'), findsNothing);
      expect(button, findsOneWidget);
      expect(fake.postedPaths, isEmpty);
    });

    testWidgets('the sign-out-everywhere dialog covers the nav bar',
        (tester) async {
      tester.view.physicalSize = const Size(2400, 7200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final router = await pumpShell(tester);
      router.go('/profile');
      await tester.pumpAndSettle();

      final entry = find.widgetWithText(TextButton, 'Sign out of all devices');
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      // The title and its confirm action share the phrase — two spans
      // inside the single dialog.
      expect(find.text('Sign out everywhere'), findsNWidgets(2));

      await tapProfileSlot(tester);

      // Barrier swallowed the tap: the dialog dismissed and Profile is
      // still the active branch.
      expect(find.text('Sign out everywhere'), findsNothing);
      expect(entry, findsOneWidget);
      expect(fake.postedPaths, isEmpty);
    });
  });
}
