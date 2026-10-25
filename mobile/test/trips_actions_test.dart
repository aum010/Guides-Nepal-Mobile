import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/core/network/api_exception.dart';
import 'package:guides_nepal/features/auth/auth_controller.dart';
import 'package:guides_nepal/features/trips/trips_screen.dart';
import 'package:guides_nepal/l10n/app_strings.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

/// Minimal signed-in session for the Trips tab.
class _FakeAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
      );
}

Map<String, dynamic> _bookingJson({
  required int id,
  required String title,
  required String status,
  String city = 'Pokhara',
  int guests = 2,
  double price = 200,
}) =>
    {
      'id': id,
      'experience_id': 7,
      'experience_title': title,
      'city': city,
      'date': '2026-11-02T00:00:00Z',
      'guests': guests,
      'price': price,
      'status': status,
      'user_id': 11,
      'created_at': '2026-10-21T09:00:00Z',
      'image': null,
    };

/// Scripted transport for the trips list plus the cancel/archive actions.
/// The fake holds the server-side list and mutates it on cancel/archive,
/// so a refetch after the action reflects the real state transition.
class _FakeTripsApi extends ApiClient {
  _FakeTripsApi(this._server);

  final List<Map<String, dynamic>> _server;

  final List<String> postedPaths = [];

  /// When set, the matching POST parks until the completer completes.
  Completer<void>? actionGate;
  ApiException? actionError;

  List<Map<String, dynamic>> get server => _server;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    if (path == '/bookings/') {
      return _ok(_server.map((b) => Map<String, dynamic>.of(b)).toList());
    }
    throw ApiException(kind: ApiFailureKind.notFound, message: 'Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    postedPaths.add(path);
    final match = RegExp(r'^/bookings/(\d+)/(cancel|archive)$').firstMatch(path);
    if (match == null) {
      throw ApiException(kind: ApiFailureKind.notFound, message: 'Unexpected POST $path');
    }
    final gate = actionGate;
    if (gate != null) await gate.future;
    final error = actionError;
    if (error != null) throw error;

    final id = int.parse(match.group(1)!);
    final action = match.group(2)!;
    final index = _server.indexWhere((b) => b['id'] == id);
    if (index == -1) {
      throw ApiException(kind: ApiFailureKind.notFound, message: 'Booking not found');
    }
    _server[index] = {
      ..._server[index],
      'status': action == 'cancel' ? 'cancelled' : 'archived',
    };
    return _ok(Map<String, dynamic>.of(_server[index]));
  }

  Response<dynamic> _ok(Object data) =>
      Response(data: data, requestOptions: RequestOptions(path: '/'));
}

/// Cancel/archive actions on the Trips tab, against a mocked API layer.
/// The list and both actions run through the real `BookingRepository`
/// and `Booking.fromJson`, so the status transitions verified here are
/// the ones the backend contract defines.
void main() {
  late _FakeTripsApi fake;
  late GoRouter router;

  Future<void> pumpTrips(
    WidgetTester tester, {
    List<Map<String, dynamic>>? server,
  }) async {
    fake = _FakeTripsApi(server ??
        [
          _bookingJson(id: 1, title: 'Sunrise over Sarangkot', status: 'upcoming'),
          _bookingJson(id: 2, title: 'Bhaktapur food walk', status: 'completed'),
        ]);
    router = GoRouter(
      initialLocation: '/trips',
      routes: [
        GoRoute(path: '/trips', builder: (_, __) => const TripsScreen()),
        GoRoute(
          path: '/explore',
          builder: (_, __) => const Scaffold(body: Text('explore-screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(fake),
          authControllerProvider.overrideWith(_FakeAuthController.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> drainSnackbars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// Taps the tile's action and confirms the cancellation dialog.
  Future<void> cancelFirstTrip(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(AppButton, 'Cancel trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel trip'));
    await tester.pumpAndSettle();
  }

  testWidgets('live trips offer cancel; terminal trips offer archive',
      (tester) async {
    await pumpTrips(tester);

    expect(find.text('Sunrise over Sarangkot'), findsOneWidget);
    expect(find.text('UPCOMING'), findsOneWidget);
    expect(find.text('Bhaktapur food walk'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);

    // One action per tile, matched to the booking's state.
    final cancelButtons = find.widgetWithText(AppButton, 'Cancel trip');
    final archiveButtons = find.widgetWithText(AppButton, 'Archive');
    expect(cancelButtons, findsOneWidget);
    expect(archiveButtons, findsOneWidget);
    expect(fake.postedPaths, isEmpty);
  });

  testWidgets('cancelling asks for confirmation first', (tester) async {
    await pumpTrips(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Cancel trip'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel this trip?'), findsOneWidget);
    expect(fake.postedPaths, isEmpty); // nothing sent yet

    // Backing out leaves everything untouched.
    await tester.tap(find.widgetWithText(TextButton, 'Keep trip'));
    await tester.pumpAndSettle();

    expect(find.text('UPCOMING'), findsOneWidget);
    expect(fake.postedPaths, isEmpty);
    expect(fake.server.first['status'], 'upcoming');
  });

  testWidgets('confirmed cancellation posts, refreshes and flips the chip',
      (tester) async {
    await pumpTrips(tester);

    await cancelFirstTrip(tester);

    expect(fake.postedPaths, ['/bookings/1/cancel']);
    // The refetch returns the server's new state — tile now reads cancelled.
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(find.text('UPCOMING'), findsNothing);
    // A cancelled trip offers archive, not cancel.
    expect(find.widgetWithText(AppButton, 'Archive'), findsNWidgets(2));
    expect(find.widgetWithText(AppButton, 'Cancel trip'), findsNothing);
  });

  testWidgets('archive clears a terminal trip to ARCHIVED', (tester) async {
    await pumpTrips(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Archive'));
    await tester.pumpAndSettle();

    expect(fake.postedPaths, ['/bookings/2/archive']);
    expect(find.text('ARCHIVED'), findsOneWidget);
    // The archived tile shows no further actions; the live trip still can
    // be cancelled.
    expect(find.widgetWithText(AppButton, 'Archive'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Cancel trip'), findsOneWidget);
  });

  testWidgets('a failed cancel keeps the trip and surfaces the error',
      (tester) async {
    await pumpTrips(tester);
    fake.actionError = ApiException(
      kind: ApiFailureKind.server,
      statusCode: 500,
      message: 'Guides Nepal is having trouble right now. Please try again.',
    );

    await cancelFirstTrip(tester);

    expect(
      find.text('Guides Nepal is having trouble right now. Please try again.'),
      findsOneWidget,
    );
    // Unchanged on screen and on the server.
    expect(find.text('UPCOMING'), findsOneWidget);
    expect(fake.server.first['status'], 'upcoming');
    await drainSnackbars(tester);

    // Retry succeeds once the server recovers.
    fake.actionError = null;
    await cancelFirstTrip(tester);
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(fake.postedPaths, hasLength(2));
  });

  testWidgets('only one action request leaves the app while in flight',
      (tester) async {
    await pumpTrips(tester);
    final gate = Completer<void>();
    fake.actionGate = gate;

    await tester.tap(find.widgetWithText(AppButton, 'Cancel trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel trip'));
    await tester.pump();
    expect(fake.postedPaths, ['/bookings/1/cancel']);

    // The tile's button is in its loading state (label swapped for a
    // spinner, so find it by the label property); a second tap is a no-op.
    final tileAction = find.byWidgetPredicate(
      (w) => w is AppButton && w.label == 'Cancel trip',
    );
    expect(tester.widget<AppButton>(tileAction).loading, isTrue);
    await tester.tap(tileAction);
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(fake.postedPaths, ['/bookings/1/cancel']); // still exactly one
    expect(find.text('CANCELLED'), findsOneWidget);
  });

  testWidgets('empty trips state invites the traveler to explore',
      (tester) async {
    await pumpTrips(tester, server: []);

    expect(find.text('No trips booked yet'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, AppStrings.exploreExperiences));
    await tester.pumpAndSettle();
    expect(find.text('explore-screen'), findsOneWidget);
  });
}
