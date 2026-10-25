// Repro harness for the live-preview crash: the full app, signed in, lands
// on `/home` and (on web debug) hits `InheritedElement.notifyClients`
// assertions — framework.dart:6430 "check that it really is our descendant"
// then 6281 `_dependents.isEmpty`. If the root cause is app-level, this test
// fails with the primary exception's full stack; if it passes, the failure is
// web/runtime-specific rather than in the widget tree itself.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/app/app.dart';
import 'package:guides_nepal/features/auth/auth_repository.dart';
import 'package:guides_nepal/shared/models/app_user.dart';

/// Auth state that is already signed in — bypasses secure storage and the
/// network so the first frame resolves straight to `/home`.
class _SignedInAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(
          id: 1,
          email: 'traveler@guides-nepal.com',
          firstName: 'Test',
          lastName: 'Traveler',
        ),
      );
}

void main() {
  testWidgets('signed-in home renders without framework assertions',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(() => _SignedInAuth())],
        child: const GuidesNepalApp(),
      ),
    );

    // Fixed pumps instead of pumpAndSettle: skeleton shimmer animations and
    // pending HTTP futures never settle in the test environment.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      find.textContaining('Where will you explore today?'),
      findsOneWidget,
      reason: 'Home body should render; a thrown framework assertion '
          'will have failed this test earlier with its stack trace.',
    );
  });
}
