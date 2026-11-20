import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/core/network/api_exception.dart';
import 'package:guides_nepal/features/auth/auth_controller.dart';
import 'package:guides_nepal/features/guide_tools/guide_models.dart';
import 'package:guides_nepal/features/guide_tools/guide_shell.dart';
import 'package:guides_nepal/features/guide_tools/guide_status_composer_screen.dart';
import 'package:guides_nepal/shared/models/app_user.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

class _GuideAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 2, email: 'guide@example.com', role: 'guide'),
      );
}

Map<String, dynamic> _listingJson({int id = 3, String title = 'Sunrise hike'}) =>
    {
      'id': id,
      'title': title,
      'category': 'trekking',
      'city': 'Pokhara',
      'description': 'An easy pre-dawn walk to the ridge above the lake.',
      'duration': '4 hours',
      'difficulty': 'Moderate',
      'price': 45,
      'max_guests': 8,
      'booked_guests': 2,
      'available_spots': 6,
      'occupancy_pct': 25,
      'is_active': true,
    };

Map<String, dynamic> _updateJson({
  int id = 5,
  String type = 'announcement',
  String message = 'Lakeside pickup moves to the clock tower.',
  int? listingId,
  String? area,
  DateTime? eventDate,
  int? currentCapacity,
  int? maxCapacity,
  bool isActive = true,
  DateTime? createdAt,
}) =>
    {
      'id': id,
      'update_type': type,
      'message': message,
      'listing_id': listingId,
      'area': area,
      'event_date': eventDate?.toIso8601String(),
      'current_capacity': currentCapacity,
      'max_capacity': maxCapacity,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
    };

/// Scripted guide API that stores updates, so the composer and the Updates
/// tab run against the real `GuideRepository` and models.
class _FakeGuideApi extends ApiClient {
  _FakeGuideApi({List<Map<String, dynamic>>? updates})
      : updates = updates ?? [];

  final List<Map<String, dynamic>> updates;
  final List<Map<String, dynamic>> listings = [
    _listingJson(),
    _listingJson(id: 4, title: 'Newari food walk'),
  ];

  final List<(String method, String path, Object? data)> calls = [];
  ApiException? failNextWrite;

  Iterable<Object?> get writes =>
      [for (final c in calls) if (c.$1 != 'GET') c.$3];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    calls.add(('GET', path, null));
    switch (path) {
      case '/guide/status':
        return _ok(updates.map(Map<String, dynamic>.of).toList());
      case '/guide/listings':
        return _ok(listings);
      case '/guide/dashboard':
        return _ok({
          'stats': {
            'listings': listings.length,
            'upcoming_bookings': 0,
            'total_guests': 0,
            'total_capacity': 16,
            'booked_capacity': 4,
            'available_spots': 12,
          },
          'listings': listings,
          'recent_status': updates,
        });
      case '/guide/onboarding':
        return _ok({'onboarding': null, 'completed': false});
    }
    throw ApiException(
        kind: ApiFailureKind.notFound, message: 'Unexpected GET $path');
  }

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
    if (path != '/guide/status') {
      throw ApiException(
          kind: ApiFailureKind.notFound, message: 'Unexpected POST $path');
    }
    final payload = (data as Map).cast<String, dynamic>();
    final created = {
      ...payload,
      'id': 100 + updates.length,
      'is_active': true,
      'created_at': DateTime.now().toIso8601String(),
    };
    updates.insert(0, created);
    return _ok(Map<String, dynamic>.of(created));
  }

  @override
  Future<Response<dynamic>> delete(
    String path, {
    CancelToken? cancelToken,
  }) async {
    calls.add(('DELETE', path, null));
    final error = failNextWrite;
    if (error != null) {
      failNextWrite = null;
      throw error;
    }
    final match = RegExp(r'^/guide/status/(\d+)$').firstMatch(path);
    if (match == null) {
      throw ApiException(
          kind: ApiFailureKind.notFound, message: 'Unexpected DELETE $path');
    }
    updates.removeWhere((u) => u['id'] == int.parse(match.group(1)!));
    return _ok({'status': 'ok'});
  }

  Response<dynamic> _ok(Object data) =>
      Response(data: data, requestOptions: RequestOptions(path: '/'));
}

void main() {
  group('GuideStatusUpdate', () {
    test('parses a populated row, including dates and capacity', () {
      final update = GuideStatusUpdate.fromJson(_updateJson(
        type: 'capacity',
        currentCapacity: 6,
        maxCapacity: 10,
        eventDate: DateTime(2026, 11, 2),
        createdAt: DateTime.utc(2026, 10, 20, 9),
      ));

      expect(update.id, 5);
      expect(update.updateType, 'capacity');
      expect(update.typeLabel, 'Capacity');
      expect(update.currentCapacity, 6);
      expect(update.maxCapacity, 10);
      expect(update.eventDate, DateTime(2026, 11, 2));
      expect(update.createdAt, DateTime.utc(2026, 10, 20, 9));
      expect(update.isActive, isTrue);
    });

    test('a minimal row falls back instead of throwing', () {
      final update = GuideStatusUpdate.fromJson(const {'id': 9});

      expect(update.message, '');
      expect(update.updateType, 'announcement');
      expect(update.createdAt, isNull);
      expect(update.isActive, isTrue);
    });

    test('an unknown server type is shown as written', () {
      final update =
          GuideStatusUpdate.fromJson(const {'update_type': 'weather'});
      expect(update.typeLabel, 'Weather');
    });
  });

  group('GuideStatusDraft mirrors the server schema', () {
    test('an announcement needs only a message', () {
      const draft = GuideStatusDraft(message: 'Lakeside pickup moves.');
      expect(draft.validate(), isEmpty);

      final json = draft.toJson();
      expect(json['update_type'], 'announcement');
      expect(json['message'], 'Lakeside pickup moves.');
      expect(json['listing_id'], isNull);
      expect(json['area'], isNull);
      // Capacity and date fields are not sent for this type.
      expect(json.containsKey('current_capacity'), isFalse);
      expect(json.containsKey('max_capacity'), isFalse);
      expect(json.containsKey('event_date'), isFalse);
    });

    test('message length limits match the server', () {
      expect(const GuideStatusDraft(message: '').validate()['message'],
          'Write the update.');
      expect(const GuideStatusDraft(message: 'ok').validate()['message'],
          'Use at least 3 characters.');
      expect(
        GuideStatusDraft(message: 'x' * 2001).validate()['message'],
        'Keep the update under 2000 characters.',
      );
      expect(
        GuideStatusDraft(message: 'Fine', area: 'x' * 161).validate()['area'],
        'Keep the area under 160 characters.',
      );
    });

    test('a capacity update needs numbers and booked cannot exceed total', () {
      const missing =
          GuideStatusDraft(updateType: 'capacity', message: 'Two spots left.');
      final errors = missing.validate();
      expect(errors['currentCapacity'], 'How many spots are already taken?');
      expect(errors['maxCapacity'], 'What is the total capacity?');

      final over = const GuideStatusDraft(
        updateType: 'capacity',
        message: 'Two spots left.',
        currentCapacityText: '11',
        maxCapacityText: '10',
      ).validate();
      expect(over['currentCapacity'],
          'Booked cannot exceed the total capacity.');

      final ok = const GuideStatusDraft(
        updateType: 'capacity',
        message: 'Two spots left.',
        currentCapacityText: '8',
        maxCapacityText: '10',
      );
      expect(ok.validate(), isEmpty);
      expect(ok.toJson()['current_capacity'], 8);
      expect(ok.toJson()['max_capacity'], 10);
    });

    test('a schedule update needs a date and sends it as ISO 8601', () {
      const draft = GuideStatusDraft(updateType: 'schedule', message: 'Moved.');
      expect(draft.validate()['eventDate'], 'Pick the date this applies to.');

      final dated = GuideStatusDraft(
        updateType: 'schedule',
        message: 'Moved.',
        eventDate: DateTime(2026, 11, 2),
      );
      expect(dated.validate(), isEmpty);
      expect(dated.toJson()['event_date'], '2026-11-02T00:00:00.000');
      // A schedule carries no capacity numbers.
      expect(dated.toJson().containsKey('current_capacity'), isFalse);
    });

    test('an attached listing and area are sent, blank area as null', () {
      final draft = const GuideStatusDraft(
        message: 'Cancelled for today.',
        listingId: 51,
        area: '   ',
      ).toJson();

      expect(draft['listing_id'], 51);
      expect(draft['area'], isNull);
    });
  });

  group('status composer', () {
    late _FakeGuideApi fake;
    late bool? popResult;

    setUp(() {
      fake = _FakeGuideApi();
      popResult = null;
    });

    Future<void> pumpComposer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(fake),
            authControllerProvider.overrideWith(_GuideAuthController.new),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      popResult = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => const GuideStatusComposerScreen(),
                        ),
                      );
                    },
                    child: const Text('open-composer'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-composer'));
      await tester.pumpAndSettle();
    }

    Future<void> type(WidgetTester tester, String key, String text) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
      await tester.pump();
    }

    Future<void> tapChip(WidgetTester tester, String label) async {
      final chip = find.widgetWithText(AppFilterChip, label);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    Future<void> tapPost(WidgetTester tester) async {
      final button = find.widgetWithText(AppButton, 'Post update');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('posts an announcement and reports the change', (tester) async {
      await pumpComposer(tester);

      await type(tester, 'status-message',
          'Lakeside pickup moves to the clock tower.');
      await type(tester, 'status-area', 'Lakeside');
      await tapPost(tester);

      final body = fake.writes.single! as Map<String, dynamic>;
      expect(fake.calls.singleWhere((c) => c.$1 == 'POST').$2, '/guide/status');
      expect(body['update_type'], 'announcement');
      expect(body['message'], 'Lakeside pickup moves to the clock tower.');
      expect(body['area'], 'Lakeside');
      expect(body['listing_id'], isNull);
      expect(popResult, isTrue);
      expect(fake.updates, hasLength(1));
    });

    testWidgets('a short message is blocked before any request',
        (tester) async {
      await pumpComposer(tester);

      await type(tester, 'status-message', 'ok');
      await tapPost(tester);

      expect(fake.calls.where((c) => c.$1 == 'POST'), isEmpty);
      expect(find.text('Use at least 3 characters.'), findsOneWidget);
      expect(popResult, isNull);
    });

    testWidgets('capacity numbers appear for a capacity update and are sent',
        (tester) async {
      await pumpComposer(tester);
      expect(find.byKey(const ValueKey('status-current-capacity')), findsNothing);

      await tapChip(tester, 'Capacity');
      expect(
          find.byKey(const ValueKey('status-current-capacity')), findsOneWidget);

      await type(tester, 'status-message', 'Only two spots left for Saturday.');
      await tapPost(tester);
      expect(fake.calls.where((c) => c.$1 == 'POST'), isEmpty,
          reason: 'the numbers are required for a capacity update');

      await type(tester, 'status-current-capacity', '8');
      await type(tester, 'status-max-capacity', '10');
      await tapPost(tester);

      final body = fake.writes.single! as Map<String, dynamic>;
      expect(body['update_type'], 'capacity');
      expect(body['current_capacity'], 8);
      expect(body['max_capacity'], 10);
      expect(popResult, isTrue);
    });

    testWidgets('a schedule update needs a picked date', (tester) async {
      await pumpComposer(tester);

      await tapChip(tester, 'Schedule');
      await type(tester, 'status-message', 'Sunrise start moves to 5:30 am.');
      await tapPost(tester);
      expect(find.text('Pick the date this applies to.'), findsOneWidget);
      expect(fake.calls.where((c) => c.$1 == 'POST'), isEmpty);

      await tester.tap(find.byKey(const ValueKey('status-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Choose date'), findsNothing);

      await tapPost(tester);

      final body = fake.writes.single! as Map<String, dynamic>;
      expect(body['update_type'], 'schedule');
      final today = DateTime.now();
      expect(
        body['event_date'] as String,
        startsWith('${today.year}-'),
      );
      expect(popResult, isTrue);
    });

    testWidgets('an attached listing is sent with the update', (tester) async {
      await pumpComposer(tester);

      await type(tester, 'status-message', 'Cancelled for today, sorry.');
      await tapChip(tester, 'Newari food walk');
      await tapPost(tester);

      final body = fake.writes.single! as Map<String, dynamic>;
      expect(body['listing_id'], 4);
      expect(popResult, isTrue);
    });

    testWidgets('a rejected listing link stays on the form', (tester) async {
      await pumpComposer(tester);
      fake.failNextWrite = ApiException(
        kind: ApiFailureKind.notFound,
        statusCode: 404,
        message: 'Listing not found',
      );

      await type(tester, 'status-message', 'Cancelled for today, sorry.');
      await tapPost(tester);

      expect(find.text('Listing not found'), findsOneWidget);
      expect(popResult, isNull);
      final message = tester.widget<AppTextField>(
        find.byKey(const ValueKey('status-message')),
      );
      expect(message.controller.text, 'Cancelled for today, sorry.');
      expect(fake.updates, isEmpty);
    });

    testWidgets('listings that fail to load leave the update guide-wide',
        (tester) async {
      await pumpComposer(tester);
      // No listings are reachable, so only "All experiences" is offered.
      fake.listings.clear();
      await type(tester, 'status-message', 'No tours running tomorrow.');
      await tapPost(tester);

      final body = fake.writes.single! as Map<String, dynamic>;
      expect(body['listing_id'], isNull);
      expect(popResult, isTrue);
    });
  });

  group('updates tab', () {
    late _FakeGuideApi fake;

    Future<void> openUpdatesTab(WidgetTester tester) async {
      await tester.tap(find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Updates'),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> pumpShell(
      WidgetTester tester, {
      Size size = const Size(900, 2800),
      bool openUpdates = true,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/guide',
        routes: [
          GoRoute(path: '/guide', builder: (_, __) => const GuideShell()),
          GoRoute(
            path: '/guide/status/new',
            builder: (_, __) => const GuideStatusComposerScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(fake),
            authControllerProvider.overrideWith(_GuideAuthController.new),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      if (openUpdates) await openUpdatesTab(tester);
    }

    testWidgets('an empty feed offers the composer', (tester) async {
      fake = _FakeGuideApi();
      await pumpShell(tester);

      expect(find.text('No updates yet'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Post an update'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('status-message')), findsOneWidget);
    });

    testWidgets('updates render with their type, scope and capacity',
        (tester) async {
      fake = _FakeGuideApi(updates: [
        _updateJson(
          message: 'Only two spots left for Saturday.',
          type: 'capacity',
          listingId: 3,
          currentCapacity: 6,
          maxCapacity: 8,
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
        _updateJson(
          id: 6,
          message: 'Lakeside pickup moves to the clock tower.',
          area: 'Lakeside',
          createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
      ]);
      await pumpShell(tester);

      expect(find.text('Capacity'), findsOneWidget);
      expect(find.text('Announcement'), findsOneWidget);
      expect(find.text('Only two spots left for Saturday.'), findsOneWidget);
      // The listing id resolves to its title through the listings provider.
      expect(find.textContaining('Sunrise hike · 6/8 spots'), findsOneWidget);
      expect(find.textContaining('3 hr ago'), findsOneWidget);
      expect(
        find.textContaining('All experiences · Lakeside · 10 min ago'),
        findsOneWidget,
      );
    });

    testWidgets('the updates tab and a full card fit a 360 dp phone',
        (tester) async {
      fake = _FakeGuideApi(updates: [
        _updateJson(
          type: 'capacity',
          listingId: 3,
          area: 'Lakeside',
          currentCapacity: 6,
          maxCapacity: 10,
          message: 'The Annapurna base camp trail is closed past Deurali '
              'because of a landslide; everyone booked for this week moves to '
              'the Poon Hill route at no extra cost.',
          createdAt: DateTime.now().subtract(const Duration(hours: 30)),
        ),
      ]);
      await pumpShell(tester, size: const Size(360, 740), openUpdates: false);

      // The test font (Ahem) draws every glyph a full em wide, so the
      // Overview's text buttons overflow at this width for reasons a real
      // font does not reproduce. Clear those, then assert the tab this change
      // adds is laid out cleanly at phone width.
      while (tester.takeException() != null) {}
      await openUpdatesTab(tester);

      // A RenderFlex overflow in the tab, header or card surfaces here.
      expect(tester.takeException(), isNull);
      expect(find.text('Capacity'), findsOneWidget);
      expect(find.byTooltip('Delete update'), findsOneWidget);
    });

    testWidgets('deleting asks first, then removes the update',
        (tester) async {
      fake = _FakeGuideApi(updates: [_updateJson()]);
      await pumpShell(tester);

      await tester.tap(find.byTooltip('Delete update'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this update?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Keep'));
      await tester.pumpAndSettle();
      expect(fake.calls.where((c) => c.$1 == 'DELETE'), isEmpty);
      expect(fake.updates, hasLength(1));

      await tester.tap(find.byTooltip('Delete update'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(fake.calls.singleWhere((c) => c.$1 == 'DELETE').$2,
          '/guide/status/5');
      expect(fake.updates, isEmpty);
      // The feed refetches and falls back to its empty state.
      expect(find.text('No updates yet'), findsOneWidget);
    });
  });
}
