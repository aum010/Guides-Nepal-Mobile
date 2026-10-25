import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/core/network/api_exception.dart';
import 'package:guides_nepal/features/auth/auth_controller.dart';
import 'package:guides_nepal/features/help/contact_screen.dart';
import 'package:guides_nepal/features/help/faq_screen.dart';
import 'package:guides_nepal/shared/widgets/app_button.dart';

/// Signed-out controller: the help pages are public, and a traveller who
/// has been signed out must still be able to reach support.
class _SignedOutAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedOut);
}

/// Scripted API that records every write, so the Contact form runs against
/// the real `apiClientProvider` wiring without a network.
class _FakeApi extends ApiClient {
  final List<(String method, String path, Object? data)> calls = [];
  ApiException? failNextWrite;

  Iterable<Object?> get writes =>
      [for (final c in calls) if (c.$1 != 'GET') c.$3];

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    calls.add(('POST', path, data));
    final error = failNextWrite;
    if (error != null) {
      failNextWrite = null;
      throw error;
    }
    if (path != '/inquiries') {
      throw ApiException(
          kind: ApiFailureKind.notFound, message: 'Unexpected POST $path');
    }
    return Response(
      data: {'status': 'ok', 'id': 1, 'message': 'Inquiry received'},
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  Future<void> pumpContact(WidgetTester tester, _FakeApi fake) async {
    tester.view.physicalSize = const Size(900, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(fake),
          authControllerProvider.overrideWith(_SignedOutAuthController.new),
        ],
        child: const MaterialApp(home: ContactScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Aarav Tester');
    await tester.enterText(fields.at(1), 'aarav@example.com');
    await tester.enterText(fields.at(2), 'Booking question');
    await tester.enterText(
      fields.at(3),
      'Can I book the Poon Hill trek for two people next week?',
    );
    await tester.pump();
  }

  Future<void> tapSend(WidgetTester tester) async {
    final button = find.widgetWithText(AppButton, 'Send message');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('FAQ page', () {
    testWidgets('a question expands to its answer and collapses again',
        (tester) async {
      tester.view.physicalSize = const Size(900, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: FaqScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('What is Guides Nepal?'), findsOneWidget);
      expect(find.textContaining('connects travellers with independent'),
          findsNothing);

      await tester.tap(find.text('What is Guides Nepal?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('connects travellers with independent'),
          findsOneWidget);

      // Only one answer is open at a time: expanding another hides this one.
      await tester.tap(find.text('What is Maila Dai?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('connects travellers with independent'),
          findsNothing);
      expect(find.textContaining('in-app travel assistant'), findsOneWidget);

      // The route out to Contact is offered at the end of the page.
      expect(find.widgetWithText(AppButton, 'Contact us'), findsOneWidget);
    });
  });

  group('Contact form', () {
    testWidgets('an incomplete form never reaches the network', (tester) async {
      final fake = _FakeApi();
      await pumpContact(tester, fake);

      await tapSend(tester);

      expect(fake.calls, isEmpty);
      expect(find.text('Please enter your name'), findsOneWidget);
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please add a subject'), findsOneWidget);
      // The success view has not replaced the form.
      expect(find.byType(TextFormField), findsNWidgets(4));
    });

    testWidgets('a valid message posts to /inquiries and confirms',
        (tester) async {
      final fake = _FakeApi();
      await pumpContact(tester, fake);

      await fillForm(tester);
      await tapSend(tester);

      final post = fake.calls.singleWhere((c) => c.$1 == 'POST');
      expect(post.$2, '/inquiries');
      final body = (post.$3 as Map).cast<String, dynamic>();
      expect(body['name'], 'Aarav Tester');
      expect(body['email'], 'aarav@example.com');
      expect(body['subject'], 'Booking question');
      expect(body['category'], 'general');
      expect(body['message'], startsWith('Can I book the Poon Hill trek'));

      expect(find.text('Message sent'), findsOneWidget);
      expect(find.textContaining('aarav@example.com'), findsOneWidget);
      // The confirmation offers starting over without leaving the page.
      expect(
          find.widgetWithText(AppButton, 'Send another message'), findsOneWidget);
    });

    testWidgets('a server failure keeps the form and shows the error',
        (tester) async {
      final fake = _FakeApi()
        ..failNextWrite = ApiException(
          kind: ApiFailureKind.server,
          statusCode: 500,
          message: 'Guides Nepal is having trouble right now. Please try again.',
        );
      await pumpContact(tester, fake);

      await fillForm(tester);
      await tapSend(tester);

      expect(
        find.text('Guides Nepal is having trouble right now. Please try again.'),
        findsOneWidget,
      );
      // Still on the form, with everything typed still there.
      expect(find.byType(TextFormField), findsNWidgets(4));
      final messageField = tester.widget<TextFormField>(find.byType(TextFormField).at(3));
      expect((messageField.controller?.text ?? ''), contains('Poon Hill'));
    });
  });
}
