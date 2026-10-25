import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/features/auth/auth_repository.dart';
import 'package:guides_nepal/features/auth/sign_in_screen.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

/// Captures sign-in calls without touching secure storage or the network.
class _FakeAuthController extends AuthController {
  String? email;
  String? password;

  @override
  AuthState build() => const AuthState(status: AuthStatus.signedOut);

  @override
  Future<void> signIn({required String email, required String password}) async {
    this.email = email;
    this.password = password;
  }
}

/// Sign-in form validation and submit wiring. The controller is faked (no
/// storage/network) and the screen sits in a minimal GoRouter so its
/// post-login `context.go('/home')` resolves.
void main() {
  late _FakeAuthController fake;
  late GoRouter router;

  Future<void> pumpSignIn(WidgetTester tester) async {
    fake = _FakeAuthController();
    router = GoRouter(
      initialLocation: '/sign-in',
      routes: [
        GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('home-screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(() => fake)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(AppButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  testWidgets('empty form shows required-field errors', (tester) async {
    await pumpSignIn(tester);
    await submit(tester);

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    // Validation failed → the controller was never called.
    expect(fake.email, isNull);
  });

  testWidgets('rejects malformed email', (tester) async {
    await pumpSignIn(tester);
    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await submit(tester);

    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Email is required'), findsNothing);
    expect(fake.email, isNull);
  });

  testWidgets('valid input submits trimmed email and navigates home',
      (tester) async {
    await pumpSignIn(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, '  traveler@example.com  ');
    await tester.enterText(fields.last, 'secret-pass');
    await submit(tester);

    // Reached the controller with normalized values…
    expect(fake.email, 'traveler@example.com');
    expect(fake.password, 'secret-pass');
    // …and the success path navigates (no field errors ever rendered).
    expect(find.text('home-screen'), findsOneWidget);
    expect(find.text('Email is required'), findsNothing);
    expect(find.text('Enter a valid email'), findsNothing);
    expect(find.text('Password is required'), findsNothing);
  });

  testWidgets('shows the sign-up link for new travelers', (tester) async {
    await pumpSignIn(tester);
    expect(find.textContaining("Don't have an account?"), findsOneWidget);
  });
}
