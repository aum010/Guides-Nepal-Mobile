import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/core/storage/token_storage.dart';
import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/features/auth/auth_repository.dart';
import 'package:guides_nepal/features/auth/forgot_password_screen.dart';
import 'package:guides_nepal/l10n/app_strings.dart';
import 'package:guides_nepal/shared/models/app_user.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

/// Records the reset request without touching the network. The real repository
/// returns whatever message the server sent, so the fake does the same.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(ApiClient(), TokenStorage());

  final requested = <String>[];
  String reply = 'If an account exists, a reset link is on its way.';
  Object? failure;

  @override
  Future<String> requestPasswordReset(String email) async {
    requested.add(email);
    if (failure != null) throw failure!;
    return reply;
  }

  @override
  Future<AuthState> restoreSession() async =>
      const AuthState(status: AuthStatus.signedOut);

  @override
  Future<AppUser> fetchProfile() async => throw UnimplementedError();
}

void main() {
  late _FakeAuthRepository repo;

  Future<void> pumpScreen(WidgetTester tester) async {
    repo = _FakeAuthRepository();
    final router = GoRouter(
      initialLocation: '/forgot-password',
      routes: [
        GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/contact',
          builder: (_, __) => const Scaffold(body: Text('contact-screen')),
        ),
        GoRoute(
          path: '/sign-in',
          builder: (_, __) => const Scaffold(body: Text('sign-in-screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('rejects an empty email without calling the backend',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.widgetWithText(AppButton, AppStrings.sendResetLink));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.emailRequired), findsOneWidget);
    expect(repo.requested, isEmpty);
  });

  testWidgets('sends the trimmed email and shows the server message',
      (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextFormField), '  asha@example.com ');
    await tester.tap(find.widgetWithText(AppButton, AppStrings.sendResetLink));
    await tester.pumpAndSettle();

    expect(repo.requested, ['asha@example.com']);
    expect(find.text(AppStrings.resetLinkSentTitle), findsOneWidget);
    // The wording comes from the server — the screen never invents it.
    expect(find.text(repo.reply), findsOneWidget);
    // …and it is honest about deployments that cannot send mail.
    expect(find.text(AppStrings.resetDeliveryNote), findsOneWidget);
  });

  testWidgets('offers support when delivery cannot be confirmed',
      (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextFormField), 'asha@example.com');
    await tester.tap(find.widgetWithText(AppButton, AppStrings.sendResetLink));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, AppStrings.contactSupport));
    await tester.pumpAndSettle();
    expect(find.text('contact-screen'), findsOneWidget);
  });

  testWidgets('surfaces a backend failure in place of the confirmation',
      (tester) async {
    await pumpScreen(tester);
    repo.failure = Exception('boom');
    await tester.enterText(find.byType(TextFormField), 'asha@example.com');
    await tester.tap(find.widgetWithText(AppButton, AppStrings.sendResetLink));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.genericError), findsOneWidget);
    expect(find.text(AppStrings.resetLinkSentTitle), findsNothing);
  });
}
