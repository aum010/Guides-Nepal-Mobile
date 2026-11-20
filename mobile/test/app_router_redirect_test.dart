import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/app/router/app_router.dart';
import 'package:guides_nepal/features/auth/auth_repository.dart';
import 'package:guides_nepal/shared/models/app_user.dart';

/// Exhaustive coverage of the navigation guard: session restore, signed-out
/// allow-list, signed-in bounce, and the traveler/guide role guard.
void main() {
  const signedOut = AuthState(status: AuthStatus.signedOut);
  const restoring = AuthState(status: AuthStatus.restoring);
  const traveler = AuthState(
    status: AuthStatus.authenticated,
    user: AppUser(id: 1, email: 'traveler@example.com', role: 'traveler'),
  );
  const guide = AuthState(
    status: AuthStatus.authenticated,
    user: AppUser(id: 2, email: 'guide@example.com', role: 'guide'),
  );
  const host = AuthState(
    status: AuthStatus.authenticated,
    user: AppUser(id: 3, email: 'host@example.com', role: 'host'),
  );

  group('session restoring', () {
    test('holds on splash when already there', () {
      expect(authRedirect(restoring, '/splash'), isNull);
    });

    test('forces splash from any other location', () {
      for (final location in ['/home', '/sign-in', '/experience/foo']) {
        expect(authRedirect(restoring, location), '/splash',
            reason: 'from $location');
      }
    });
  });

  group('signed out', () {
    test('splash resolves to onboarding (never parks on splash)', () {
      expect(authRedirect(signedOut, '/splash'), '/onboarding');
    });

    test('onboarding and auth screens are allowed', () {
      for (final location in [
        '/onboarding',
        '/sign-in',
        '/sign-up',
        '/forgot-password',
      ]) {
        expect(authRedirect(signedOut, location), isNull,
            reason: 'from $location');
      }
    });

    test('public help pages stay open (support must be reachable locked out)', () {
      for (final location in ['/faq', '/contact']) {
        expect(authRedirect(signedOut, location), isNull,
            reason: 'from $location');
      }
    });

    test('everything else bounces to sign-in', () {
      for (final location in [
        '/home',
        '/explore',
        '/trips',
        '/inbox',
        '/profile',
        '/saved',
        '/profile/edit',
        '/ai',
        '/guide',
        '/guide/profile',
        '/guide/status/new',
        '/guide/listing/new',
        '/guide/listing/3',
        '/experience/foo',
        '/destination/Kathmandu',
        '/book/foo',
      ]) {
        expect(authRedirect(signedOut, location), '/sign-in',
            reason: 'from $location');
      }
    });
  });

  group('signed in', () {
    test('signed-out-only screens resolve to home', () {
      for (final location in ['/splash', '/sign-in', '/sign-up', '/onboarding']) {
        expect(authRedirect(traveler, location), '/home',
            reason: 'from $location');
      }
    });

    test('shell tabs and detail routes are allowed', () {
      for (final location in [
        '/home',
        '/explore',
        '/trips',
        '/inbox',
        '/profile',
        '/profile/edit',
        '/saved',
        '/ai',
        '/faq',
        '/contact',
        '/experience/foo',
        '/guide/7',
        '/destination/Pokhara',
        '/book/foo',
      ]) {
        expect(authRedirect(traveler, location), isNull,
            reason: 'from $location');
      }
    });
  });

  group('role guard', () {
    test('traveler cannot reach the guide workspace', () {
      expect(authRedirect(traveler, '/guide'), '/home');
    });

    test('traveler cannot reach the listing editor either', () {
      expect(authRedirect(traveler, '/guide/listing/new'), '/home');
      expect(authRedirect(traveler, '/guide/listing/3'), '/home');
    });

    test('traveler cannot edit a guide profile', () {
      expect(authRedirect(traveler, '/guide/profile'), '/home');
    });

    test('traveler cannot post a guide update', () {
      expect(authRedirect(traveler, '/guide/status/new'), '/home');
    });

    test('guide profiles stay public for travelers', () {
      expect(authRedirect(traveler, '/guide/7'), isNull);
      expect(authRedirect(traveler, '/guide/42'), isNull);
    });

    test('guide can reach the guide workspace', () {
      expect(authRedirect(guide, '/guide'), isNull);
      expect(authRedirect(guide, '/home'), isNull);
    });

    test('guide can create and edit their own listings', () {
      expect(authRedirect(guide, '/guide/listing/new'), isNull);
      expect(authRedirect(guide, '/guide/listing/3'), isNull);
    });

    test('guide can edit their own profile', () {
      expect(authRedirect(guide, '/guide/profile'), isNull);
    });

    test('guide can post updates', () {
      expect(authRedirect(guide, '/guide/status/new'), isNull);
    });
  });

  group('host workspace guard', () {
    test('host can reach the workspace and both editors', () {
      for (final location in [
        '/host',
        '/host/experience/new',
        '/host/experience/12',
        '/host/tour/new',
        '/host/tour/4',
      ]) {
        expect(authRedirect(host, location), isNull, reason: 'from $location');
      }
    });

    test('travelers are bounced out', () {
      expect(authRedirect(traveler, '/host'), '/home');
      expect(authRedirect(traveler, '/host/experience/new'), '/home');
    });

    test('guides are bounced out too — the roles are not interchangeable', () {
      expect(authRedirect(guide, '/host'), '/home');
      expect(authRedirect(guide, '/host/tour/new'), '/home');
    });

    test('a host cannot reach the guide workspace', () {
      expect(authRedirect(host, '/guide'), '/home');
      expect(authRedirect(host, '/guide/listing/new'), '/home');
    });
  });

  group('password settings', () {
    test('signed-out visitors cannot open the change-password screen', () {
      expect(authRedirect(signedOut, '/settings/password'), '/sign-in');
    });

    test('signed-in users can', () {
      expect(authRedirect(traveler, '/settings/password'), isNull);
    });

    test('the reset request is a signed-out screen, so it bounces home', () {
      expect(authRedirect(traveler, '/forgot-password'), '/home');
    });
  });
}
