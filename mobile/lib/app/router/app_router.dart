import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai_assistant/ai_assistant_screen.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/sign_up_screen.dart';
import '../../features/bookings/booking_flow.dart';
import '../../features/destinations/destination_screen.dart';
import '../../features/experiences/experience_detail_screen.dart';
import '../../features/explore/explore_screen.dart';
import '../../features/guides/guide_profile_screen.dart';
import '../../features/guide_tools/guide_profile_editor_screen.dart';
import '../../features/guide_tools/guide_shell.dart';
import '../../features/guide_tools/guide_status_composer_screen.dart';
import '../../features/guide_tools/listing_editor_screen.dart';
import '../../features/help/contact_screen.dart';
import '../../features/help/faq_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/inbox/inbox_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/saved/saved_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/trips/trips_screen.dart';
import '../app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Pure redirect decision for the current [auth] session and [location].
///
/// Kept free of BuildContext/GoRouter so it can be unit-tested exhaustively
/// (see `test/app_router_redirect_test.dart`). Returns `null` when the
/// location is allowed as-is.
String? authRedirect(AuthState auth, String location) {
  // Session still being restored — hold on the splash.
  if (auth.status == AuthStatus.restoring) {
    return location == '/splash' ? null : '/splash';
  }

  final signingIn =
      location == '/sign-in' || location == '/sign-up' || location == '/onboarding';

  // Help pages a signed-out visitor must reach without an account — a
  // traveller locked out of their session still needs support (the platform
  // serves both publicly on the web too).
  final publicHelp = location == '/faq' || location == '/contact';

  // Signed out: splash resolves to onboarding (the signed-out entry
  // experience); only onboarding and the auth screens are reachable.
  if (!auth.isAuthenticated) {
    if (location == '/splash') return '/onboarding';
    if (signingIn || publicHelp) return null;
    return '/sign-in';
  }

  // Signed in: these signed-out-only screens resolve to home.
  if (location == '/splash' ||
      location == '/sign-in' ||
      location == '/sign-up' ||
      location == '/onboarding') {
    return '/home';
  }

  // Role guard: the guide workspace, its profile editor and its listing
  // editor are closed to travelers. Guide profiles (/guide/:id) are public
  // discovery pages and stay open to everyone.
  if (_isGuideWorkspace(location) && !auth.isGuide) return '/home';
  return null;
}

/// `/guide` itself plus the guide-owned editors below it (profile, listings
/// and updates) — never the public `/guide/:id` profile pages.
bool _isGuideWorkspace(String location) =>
    location == '/guide' ||
    location == '/guide/profile' ||
    location.startsWith('/guide/listing') ||
    location.startsWith('/guide/status');

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    redirect: (context, state) => authRedirect(auth, state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/sign-up', builder: (_, __) => const SignUpScreen()),

      // Bottom-tab shell.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/explore', builder: (_, __) => const ExploreScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/trips', builder: (_, __) => const TripsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/inbox', builder: (_, __) => const InboxScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          ]),
        ],
      ),

      // Detail routes (full-screen over the shell).
      GoRoute(
        path: '/experience/:slug',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            ExperienceDetailScreen(slug: state.pathParameters['slug']!),
      ),
      // Declared before `/guide/:id`: GoRouter takes the first match, and a
      // guide's own profile editor must not resolve to a public profile page.
      GoRoute(
        path: '/guide/profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const GuideProfileEditorScreen(),
      ),
      GoRoute(
        path: '/guide/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => GuideProfileScreen(
          guideId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/destination/:city',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            DestinationScreen(city: state.pathParameters['city']!),
      ),
      GoRoute(
        path: '/book/:slug',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            BookingFlow(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/ai',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AiAssistantScreen(),
      ),
      GoRoute(
        path: '/saved',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const SavedScreen(),
      ),
      // Public help pages (open to signed-out visitors too).
      GoRoute(
        path: '/faq',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const FaqScreen(),
      ),
      GoRoute(
        path: '/contact',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ContactScreen(),
      ),

      // Guide workspace (role-guarded by the redirect above).
      GoRoute(
        path: '/guide',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const GuideShell(),
      ),
      GoRoute(
        path: '/guide/listing/new',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ListingEditorScreen(),
      ),
      GoRoute(
        path: '/guide/status/new',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const GuideStatusComposerScreen(),
      ),
      GoRoute(
        path: '/guide/listing/:id',
        parentNavigatorKey: _rootNavigatorKey,
        // A non-numeric id resolves to a listing that cannot be owned, so
        // the editor shows its "no longer available" state instead of an
        // empty create form.
        builder: (_, state) => ListingEditorScreen(
          listingId: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
        ),
      ),
    ],
  );
});
