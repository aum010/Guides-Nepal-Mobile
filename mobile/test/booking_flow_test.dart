import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/core/network/api_exception.dart';
import 'package:guides_nepal/core/utils/formatters.dart';
import 'package:guides_nepal/features/auth/auth_repository.dart';
import 'package:guides_nepal/features/bookings/booking_flow.dart';
import 'package:guides_nepal/l10n/app_strings.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

const _slug = 'everest-sunrise';

final Map<String, dynamic> _experienceJson = {
  'id': 7,
  'slug': _slug,
  'title': 'Sunrise over Sarangkot',
  'heroImage': 'https://images.example.com/sarangkot.jpg',
  'description': 'Ride up before dawn and watch the Annapurna range catch fire.',
  'host': {
    'id': 3,
    'name': 'Pemba Sherpa',
    'image': '',
    'role': 'Mountain guide',
    'rating': 4.9,
    'reviews': 210,
    'bio': 'Twenty years on these trails.',
    'languages': ['English', 'Nepali'],
    'verified': true,
    'cities': ['Pokhara'],
  },
  'price': 100,
  'duration': '3 days',
  'rating': 4.8,
  'reviews': 123,
  'city': 'Pokhara',
  'category': 'Sunrise',
};

final Map<String, dynamic> _createdBookingJson = {
  'id': 42,
  'experience_id': 7,
  'experience_title': 'Sunrise over Sarangkot',
  'city': 'Pokhara',
  'date': '2026-10-25T00:00:00Z',
  'guests': 1,
  'price': 100.0,
  'status': 'upcoming',
  'user_id': 11,
  'created_at': '2026-10-21T09:00:00Z',
  'image': 'https://images.example.com/sarangkot.jpg',
};

/// Scripted transport: routes requests by path and records what the real
/// repositories sent, so `BookingRepository` and `Booking.fromJson` run
/// unmodified — only the HTTP boundary is faked.
class _FakeApiClient extends ApiClient {
  final List<String> fetchedExperiences = [];
  final List<Map<String, dynamic>> availabilityRequests = [];
  final List<Map<String, dynamic>> created = [];

  /// What `GET /experiences/{slug}` answers; a published guide listing adds
  /// `listingId`, `maxGuests` and `availableSpots`.
  Map<String, dynamic> experienceResponse = _experienceJson;

  /// Success payload for `GET /bookings/availability`.
  Map<String, dynamic> availabilityResponse = {'available': true, 'status': 'free'};
  ApiException? availabilityError;
  ApiException? createError;

  /// When set, `POST /bookings/` parks until the completer is completed —
  /// used to observe the in-flight submission window.
  Completer<void>? createGate;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    if (path == '/experiences/$_slug') {
      fetchedExperiences.add(path);
      return _ok(experienceResponse);
    }
    if (path == '/bookings/availability') {
      availabilityRequests.add(Map.of(query ?? const {}));
      final error = availabilityError;
      if (error != null) throw error;
      return _ok(availabilityResponse);
    }
    if (path == '/bookings/') return _ok(const <dynamic>[]);
    throw ApiException(kind: ApiFailureKind.notFound, message: 'Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    if (path == '/bookings/') {
      created.add((data as Map).cast<String, dynamic>());
      final gate = createGate;
      if (gate != null) await gate.future;
      final error = createError;
      if (error != null) throw error;
      return _ok(_createdBookingJson);
    }
    throw ApiException(kind: ApiFailureKind.notFound, message: 'Unexpected POST $path');
  }

  Response<dynamic> _ok(Object data) =>
      Response(data: data, requestOptions: RequestOptions(path: '/'));
}

/// Booking flow integration tests against a mocked API layer. The flow's
/// own repositories parse the fake responses, so these cover the real
/// contract: availability gating, the `BookingCreate` payload, and the
/// confirmation the traveler actually sees.
void main() {
  late _FakeApiClient fake;
  late GoRouter router;

  Future<void> pumpBooking(
    WidgetTester tester, {
    void Function(_FakeApiClient fake)? configure,
  }) async {
    fake = _FakeApiClient();
    configure?.call(fake);
    router = GoRouter(
      initialLocation: '/book/$_slug',
      routes: [
        GoRoute(
          path: '/book/:slug',
          builder: (_, state) => BookingFlow(slug: state.pathParameters['slug']!),
        ),
        GoRoute(
          path: '/trips',
          builder: (_, __) => const Scaffold(body: Text('trips-screen')),
        ),
        GoRoute(
          path: '/explore',
          builder: (_, __) => const Scaffold(body: Text('explore-screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(fake)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Opens the date picker and accepts the preselected initial date (today).
  Future<void> pickToday(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.checkAvailability));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> tapContinue(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(AppButton, 'Continue'));
    await tester.pumpAndSettle();
  }

  /// Lets a SnackBar finish its auto-dismiss timer so no timer outlives the
  /// test.
  Future<void> drainSnackbars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// Walks date → guests → review with defaults.
  Future<void> toReviewStep(WidgetTester tester) async {
    await pickToday(tester);
    await tapContinue(tester);
    await tapContinue(tester);
  }

  testWidgets('loads the experience and offers the date step', (tester) async {
    await pumpBooking(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('When would you like to go?'), findsOneWidget);
    expect(find.text('This experience lasts 3 days.'), findsOneWidget);
    expect(fake.fetchedExperiences, ['/experiences/$_slug']);
  });

  testWidgets('continue without a date prompts and stays on step one',
      (tester) async {
    await pumpBooking(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please choose a date first.'), findsOneWidget);
    expect(find.text('When would you like to go?'), findsOneWidget);
    expect(fake.availabilityRequests, isEmpty);
    expect(fake.created, isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('picking a date queries availability for that day',
      (tester) async {
    await pumpBooking(tester);
    await tester.pumpAndSettle();

    await pickToday(tester);

    expect(fake.availabilityRequests, hasLength(1));
    expect(
      fake.availabilityRequests.single['date'],
      today().toIso8601String().substring(0, 10),
    );
    expect(find.text(Formatters.dateWithWeekday(today())), findsOneWidget);
  });

  testWidgets('a booked date is rejected and the selection is cleared',
      (tester) async {
    await pumpBooking(
      tester,
      configure: (f) =>
          f.availabilityResponse = {'available': false, 'status': 'booked'},
    );
    await tester.pumpAndSettle();

    await pickToday(tester);

    expect(
      find.text('That date is already booked. Please choose another.'),
      findsOneWidget,
    );
    // Selection cleared — the traveler is back to "check availability".
    expect(find.text(AppStrings.checkAvailability), findsOneWidget);
    expect(find.text(Formatters.dateWithWeekday(today())), findsNothing);
    await drainSnackbars(tester);
  });

  testWidgets('a reserved date shows the reserved message', (tester) async {
    await pumpBooking(
      tester,
      configure: (f) =>
          f.availabilityResponse = {'available': false, 'status': 'reserved'},
    );
    await tester.pumpAndSettle();

    await pickToday(tester);

    expect(
      find.text('That date is reserved. Please choose another.'),
      findsOneWidget,
    );
    expect(find.text(AppStrings.checkAvailability), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('availability failure is advisory and the flow continues',
      (tester) async {
    await pumpBooking(
      tester,
      configure: (f) => f.availabilityError = ApiException(
        kind: ApiFailureKind.network,
        message: 'Could not reach Guides Nepal. Check your connection.',
      ),
    );
    await tester.pumpAndSettle();

    await pickToday(tester);

    // The error is surfaced, but the pick stands — the server decides on POST.
    expect(
      find.text('Could not reach Guides Nepal. Check your connection.'),
      findsOneWidget,
    );
    expect(find.text(Formatters.dateWithWeekday(today())), findsOneWidget);
    await drainSnackbars(tester);

    await tapContinue(tester);
    expect(find.text('How many guests?'), findsOneWidget);
  });

  testWidgets('books with adjusted guests and shows the confirmation',
      (tester) async {
    await pumpBooking(tester);
    await tester.pumpAndSettle();

    await pickToday(tester);
    await tapContinue(tester);
    expect(find.text('How many guests?'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    await tapContinue(tester);
    expect(find.text('Review your booking'), findsOneWidget);
    expect(find.text('2 guests'), findsOneWidget);
    expect(find.text('\$200'), findsOneWidget); // 100 × 2

    await tester.tap(find.widgetWithText(AppButton, 'Request booking'));
    await tester.pumpAndSettle();

    expect(find.text('Request sent!'), findsOneWidget);
    expect(find.text('Booking #42'), findsOneWidget);

    final body = fake.created.single;
    expect(body['experience_id'], 7);
    expect(body['experience_title'], 'Sunrise over Sarangkot');
    expect(body['city'], 'Pokhara');
    expect(body['guests'], 2);
    expect(body['price'], 200.0);
    expect(body['image'], 'https://images.example.com/sarangkot.jpg');
    expect(DateTime.parse(body['date'] as String).toLocal(), today());
  });

  testWidgets('surfaces a submit failure and allows retrying', (tester) async {
    await pumpBooking(tester);
    await tester.pumpAndSettle();
    await toReviewStep(tester);

    fake.createError = ApiException(
      kind: ApiFailureKind.server,
      statusCode: 500,
      message: 'Guides Nepal is having trouble right now. Please try again.',
    );
    await tester.tap(find.widgetWithText(AppButton, 'Request booking'));
    await tester.pumpAndSettle();

    expect(
      find.text('Guides Nepal is having trouble right now. Please try again.'),
      findsOneWidget,
    );
    // Still on review — nothing was created and the form survived.
    expect(find.text('Review your booking'), findsOneWidget);
    await drainSnackbars(tester);

    fake.createError = null;
    await tester.tap(find.widgetWithText(AppButton, 'Request booking'));
    await tester.pumpAndSettle();

    expect(find.text('Request sent!'), findsOneWidget);
    expect(find.text('Booking #42'), findsOneWidget);
    expect(fake.created, hasLength(2)); // failed attempt + retry
  });

  testWidgets('ignores duplicate submits while one is in flight',
      (tester) async {
    await pumpBooking(tester);
    await tester.pumpAndSettle();
    await toReviewStep(tester);

    final gate = Completer<void>();
    fake.createGate = gate;

    await tester.tap(find.widgetWithText(AppButton, 'Request booking'));
    await tester.pump();

    // Second tap while loading: the button shows a spinner and is disabled.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(AppButton).last);
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Request sent!'), findsOneWidget);
    expect(fake.created, hasLength(1)); // exactly one POST ever left the app
  });

  testWidgets('confirmation "View my trips" goes to trips', (tester) async {
    await pumpBooking(tester);
    await tester.pumpAndSettle();
    await toReviewStep(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Request booking'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, 'View my trips'));
    await tester.pumpAndSettle();

    expect(find.text('trips-screen'), findsOneWidget);
  });

  testWidgets('availability is asked for this experience, not the catalogue',
      (tester) async {
    await pumpBooking(tester);
    await tester.pumpAndSettle();

    await pickToday(tester);

    // Without this the server answers for the single fallback guide's
    // calendar and a listing's own seats are never checked.
    expect(fake.availabilityRequests.single['experience_id'], 7);
  });

  testWidgets('a sold-out listing says the seats are gone', (tester) async {
    await pumpBooking(
      tester,
      configure: (f) => f.availabilityResponse = {
        'available': false,
        'status': 'full',
        'spots_left': 0,
      },
    );
    await tester.pumpAndSettle();

    await pickToday(tester);

    expect(
      find.text(
          'This trip has no seats left for the moment. Please try another experience.'),
      findsOneWidget,
    );
    expect(find.text(AppStrings.checkAvailability), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('the guest stepper stops at the seats the listing has left',
      (tester) async {
    await pumpBooking(
      tester,
      configure: (f) => f.experienceResponse = {
        ..._experienceJson,
        'listingId': 9,
        'maxGuests': 2,
        'availableSpots': 2,
      },
    );
    await tester.pumpAndSettle();

    await pickToday(tester);
    await tapContinue(tester);

    expect(find.text('2 guests left on this trip.'), findsOneWidget);

    // Two is the whole trip: the stepper refuses a third guest here rather
    // than letting the server reject the request at the last step.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('confirmation "Keep exploring" goes to explore', (tester) async {
    await pumpBooking(tester);
    await tester.pumpAndSettle();
    await toReviewStep(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Request booking'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, 'Keep exploring'));
    await tester.pumpAndSettle();

    expect(find.text('explore-screen'), findsOneWidget);
  });
}
