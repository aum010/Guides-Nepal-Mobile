import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/app/router/app_router.dart';
import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/features/auth/auth_controller.dart';
import 'package:guides_nepal/features/inbox/conversation_screen.dart';
import 'package:guides_nepal/features/inbox/inbox_screen.dart';
import 'package:guides_nepal/l10n/app_strings.dart';
import 'package:guides_nepal/shared/models/app_user.dart';
import 'package:guides_nepal/shared/models/booking.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

/// Authenticated as the traveler who owns id 11 — the sender side of the
/// fixture conversation below.
class _FakeAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(
          id: 11,
          email: 'traveler@example.com',
          firstName: 'Test',
          lastName: 'Traveler',
        ),
      );
}

final _conversation = <String, dynamic>{
  'id': 7,
  'peer': {
    'id': 5,
    'firstName': 'Mingma',
    'lastName': 'Sherpa',
    'avatarUrl': null,
    'role': 'guide',
  },
  'last_message': {
    'id': 3,
    'body': 'Gate opens at 4am',
    'sender_id': 5,
    'created_at': '2026-10-25T08:00:00Z',
  },
  'unread_count': 2,
  'created_at': '2026-10-20T08:00:00Z',
};

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
  'guide_user_id': 5,
  'guide_name': 'Mingma Sherpa',
};

/// Serves the four conversation routes plus whatever the shell branches
/// fetch; records reads and sends so tests can assert on traffic.
class _FakeInboxApi extends ApiClient {
  _FakeInboxApi({this.conversations, List<Map<String, dynamic>>? messages})
      : messages = messages ??
            [
              {
                'id': 2,
                'conversation_id': 7,
                'sender_id': 11,
                'body': 'Namaste! Is the gate open?',
                'created_at': '2026-10-25T07:00:00Z',
                'read_at': null,
              },
              {
                'id': 3,
                'conversation_id': 7,
                'sender_id': 5,
                'body': 'Gate opens at 4am',
                'created_at': '2026-10-25T08:00:00Z',
                'read_at': null,
              },
            ];

  List<Map<String, dynamic>>? conversations;
  final List<Map<String, dynamic>> messages;
  final List<String> getPaths = [];
  final List<Map<String, dynamic>> posted = [];
  final List<String> sentBodies = [];
  int _nextMessageId = 100;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    getPaths.add(path);
    return _ok(switch (path) {
      '/conversations' => conversations ?? [_conversation],
      '/bookings/' => [_booking],
      '/profile/me' => {
          'id': 11,
          'email': 'traveler@example.com',
          'firstName': 'Test',
          'lastName': 'Traveler',
          'role': 'traveler',
        },
      _ when path.endsWith('/messages') => messages,
      _ => <dynamic>[],
    });
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    final body = (data as Map?)?.cast<String, dynamic>() ?? {};
    posted.add({'path': path, ...body});

    if (path == '/conversations') {
      return _ok(_conversation);
    }
    if (path.endsWith('/messages')) {
      final created = {
        'id': _nextMessageId++,
        'conversation_id': 7,
        'sender_id': 11,
        'body': body['body'] ?? '',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'read_at': null,
      };
      messages.add(created);
      sentBodies.add(created['body'] as String);
      return _ok(created);
    }
    return _ok(<dynamic>{});
  }

  Response<dynamic> _ok(Object data) => Response(
        data: data,
        requestOptions: RequestOptions(path: '/'),
      );
}

/// Bounded pumping: skeletons pulse forever, so `pumpAndSettle` would
/// hang while a request is in flight. Stop as soon as no loading widget
/// remains — which is also what keeps the fake clock (and the screens'
/// poll timers) from advancing into their first tick.
Future<void> pumpUntilLoaded(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    final loading = tester.any(find.byType(SkeletonBox)) ||
        tester.any(find.byType(CircularProgressIndicator));
    if (!loading) return;
  }
}

void main() {
  Future<void> pumpInbox(
    WidgetTester tester, {
    required _FakeInboxApi fake,
    Duration? pollInterval = const Duration(seconds: 999),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(fake),
          authControllerProvider.overrideWith(_FakeAuthController.new),
        ],
        child: MaterialApp(
          home: InboxScreen(pollInterval: pollInterval),
        ),
      ),
    );
    await pumpUntilLoaded(tester);
  }

  group('Inbox list', () {
    testWidgets('shows peer, preview and the unread pill', (tester) async {
      final fake = _FakeInboxApi();
      await pumpInbox(tester, fake: fake);

      expect(find.text('Mingma Sherpa'), findsOneWidget);
      expect(find.text('Gate opens at 4am'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // unread pill
      expect(find.text(AppStrings.messagesSection), findsOneWidget);
      // The assistant card stays promoted above the threads.
      expect(find.text('Chat with Maila Dai'), findsOneWidget);
      // The old placeholder copy is gone for good.
      expect(find.text(AppStrings.inboxEmptyTitle), findsNothing);
    });

    testWidgets('states honestly when there are no conversations',
        (tester) async {
      final fake = _FakeInboxApi(conversations: const []);
      await pumpInbox(tester, fake: fake);

      expect(find.text(AppStrings.inboxEmptyTitle), findsOneWidget);
      expect(find.text(AppStrings.inboxEmptyBody), findsOneWidget);
      expect(find.text('Chat with Maila Dai'), findsOneWidget);
      expect(fake.getPaths, contains('/conversations'));
    });

    testWidgets('pull-to-refresh refetches conversations', (tester) async {
      final fake = _FakeInboxApi();
      await pumpInbox(tester, fake: fake);
      final reads = fake.getPaths.where((p) => p == '/conversations').length;

      await tester.drag(find.text('Mingma Sherpa'), const Offset(0, 300));
      await tester.pump(); // begin the indicator's snap-back settle
      // Give the indicator its animation time to reach the trigger point
      // and invoke onRefresh (the helper above cannot see it: the pull
      // spinner is a RefreshProgressIndicator, not a
      // CircularProgressIndicator).
      await tester.pump(const Duration(seconds: 1));
      await pumpUntilLoaded(tester);

      expect(
        fake.getPaths.where((p) => p == '/conversations').length,
        reads + 1,
      );
    });

    testWidgets('the default 15 s poll refetches conversations',
        (tester) async {
      final fake = _FakeInboxApi();
      // Constructor default — the production wiring.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(fake),
            authControllerProvider.overrideWith(_FakeAuthController.new),
          ],
          child: const MaterialApp(home: InboxScreen()),
        ),
      );
      await pumpUntilLoaded(tester);
      final reads = fake.getPaths.where((p) => p == '/conversations').length;
      expect(reads, 1);

      // Cross the first tick (15 s from initState): the provider is
      // invalidated and the list re-fetched.
      await tester.pump(const Duration(seconds: 16));
      await pumpUntilLoaded(tester);

      expect(
        fake.getPaths.where((p) => p == '/conversations').length,
        reads + 1,
      );
    });
  });

  group('Thread screen', () {
    Future<void> pumpThread(
      WidgetTester tester, {
      required _FakeInboxApi fake,
      Duration? pollInterval = const Duration(seconds: 999),
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(fake),
            authControllerProvider.overrideWith(_FakeAuthController.new),
          ],
          child: MaterialApp(
            home: ConversationScreen(
              conversationId: 7,
              pollInterval: pollInterval,
            ),
          ),
        ),
      );
      await pumpUntilLoaded(tester);
    }

    testWidgets('renders both sides of the conversation', (tester) async {
      await pumpThread(tester, fake: _FakeInboxApi());

      expect(find.text('Mingma Sherpa'), findsOneWidget); // app bar peer
      expect(find.text('Namaste! Is the gate open?'), findsOneWidget);
      expect(find.text('Gate opens at 4am'), findsOneWidget);
    });

    testWidgets('sending posts the body and shows the new bubble',
        (tester) async {
      final fake = _FakeInboxApi();
      await pumpThread(tester, fake: fake);

      await tester.enterText(find.byType(TextField), 'See you at dawn');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await pumpUntilLoaded(tester);

      expect(fake.sentBodies, contains('See you at dawn'));
      expect(find.text('See you at dawn'), findsOneWidget);
      expect(
        fake.posted.any(
          (p) => p['path'] == '/conversations/7/messages' &&
              p['body'] == 'See you at dawn',
        ),
        isTrue,
      );
    });

    testWidgets('blank sends are not transmitted', (tester) async {
      final fake = _FakeInboxApi();
      await pumpThread(tester, fake: fake);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(fake.sentBodies, isEmpty);
    });
  });

  group('Trips entry point', () {
    Future<GoRouter> pumpShell(WidgetTester tester, _FakeInboxApi fake) async {
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
      await pumpUntilLoaded(tester);
      final element = tester.element(find.byType(MaterialApp));
      return ProviderScope.containerOf(element).read(appRouterProvider);
    }

    testWidgets('"Message guide" opens the booking guide\'s thread',
        (tester) async {
      final fake = _FakeInboxApi();
      final router = await pumpShell(tester, fake);
      router.go('/trips');
      await pumpUntilLoaded(tester);
      expect(find.text('Sunrise over Sarangkot'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Message guide'));
      await pumpUntilLoaded(tester);

      // Get-or-create ran against the booking's assigned guide…
      expect(
        fake.posted.any(
          (p) =>
              p['path'] == '/conversations' && p['recipient_id'] == 5,
        ),
        isTrue,
      );
      // …and the thread opened full-screen over the shell.
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(find.text('Namaste! Is the gate open?'), findsOneWidget);
    });
  });

  group('Booking model', () {
    test('parses the guide fields used by the message entry point', () {
      final booking = Booking.fromJson(_booking);
      expect(booking.guideUserId, 5);
      expect(booking.guideName, 'Mingma Sherpa');
    });

    test('guide fields stay null on payloads without them', () {
      final json = Map<String, dynamic>.from(_booking)
        ..remove('guide_user_id')
        ..remove('guide_name');
      final booking = Booking.fromJson(json);
      expect(booking.guideUserId, isNull);
      expect(booking.guideName, isNull);
    });
  });
}
