import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/app/theme/app_theme.dart';
import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/features/auth/auth_repository.dart';
import 'package:guides_nepal/features/explore/explore_screen.dart';
import 'package:guides_nepal/features/guide_tools/guide_shell.dart';
import 'package:guides_nepal/features/home/home_shell.dart';
import 'package:guides_nepal/features/inbox/inbox_screen.dart';
import 'package:guides_nepal/features/profile/profile_edit_screen.dart';
import 'package:guides_nepal/features/profile/profile_screen.dart';
import 'package:guides_nepal/features/trips/trips_screen.dart';
import 'package:guides_nepal/shared/models/app_user.dart';

/// Design review captures, not assertions.
///
/// The app cannot be photographed from a real device in this environment, so
/// this harness renders the *real* screens — real theme, real bundled fonts,
/// real repositories — against a scripted transport, at a phone viewport, and
/// writes the pixels to `docs/screens/`. That makes a design review repeatable:
///
/// ```bash
/// flutter test test/design_capture_test.dart --dart-define=CAPTURE_SCREENS=true
/// ```
///
/// Without that define every case is skipped, so the normal suite gains nothing
/// to flake on. Images are served by the widget's own branded
/// placeholder (the transport is faked, not the photo CDN), so photography is
/// the one thing these captures cannot show.
const _capturing = bool.fromEnvironment('CAPTURE_SCREENS');

/// Signed-in session for the traveler screens.
class _TravelerAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(
          id: 11,
          email: 'traveler@guides-nepal.com',
          firstName: 'Anisha',
          lastName: 'Gurung',
        ),
      );
}

/// Signed-in session for the guide workspace.
class _GuideAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(
          id: 21,
          email: 'guide@guides-nepal.com',
          firstName: 'Mingma',
          lastName: 'Sherpa',
          role: 'guide',
        ),
      );
}

Map<String, dynamic> _host({
  int id = 1,
  String name = 'Ram Bahadur',
  String role = 'Heritage guide',
}) =>
    {
      'id': id,
      'name': name,
      'image': '',
      'role': role,
      'rating': 4.9,
      'reviews': 132,
      'bio': 'Born in Bhaktapur, guiding for eleven years.',
      'languages': ['Nepali', 'English'],
      'verified': true,
      'cities': ['Bhaktapur'],
    };

Map<String, dynamic> _experience({
  required int id,
  required String slug,
  required String title,
  required String city,
  required String category,
  required double price,
  required String duration,
  double? rating = 4.8,
  int? reviews = 45,
  int? spots,
}) =>
    {
      'id': id,
      'slug': slug,
      'title': title,
      'heroImage': '',
      'description': 'A considered, local-led look at $city.',
      'price': price,
      'duration': duration,
      'rating': rating,
      'reviews': reviews,
      'city': city,
      'category': category,
      'host': _host(),
      'availableSpots': spots,
    };

Map<String, dynamic> _booking({
  required int id,
  required String title,
  required String status,
  required String city,
  String date = '2026-11-08T00:00:00Z',
  int guests = 2,
  double price = 180,
}) =>
    {
      'id': id,
      'experience_id': 7,
      'experience_title': title,
      'city': city,
      'date': date,
      'guests': guests,
      'price': price,
      'status': status,
      'user_id': 11,
      'created_at': '2026-10-24T09:00:00Z',
      'image': null,
    };

/// One transport for every screen: the paths are the verified contracts, and
/// each returns a realistic page of rows.
class _CaptureApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    final data = switch (path) {
      '/profile/me' => const {
          'id': 11,
          'email': 'traveler@guides-nepal.com',
          'firstName': 'Anisha',
          'lastName': 'Gurung',
          'role': 'traveler',
        },
      '/experiences' => [
          _experience(
              id: 1,
              slug: 'bhaktapur-heritage-walk',
              title: 'Bhaktapur Heritage Walk',
              city: 'Bhaktapur',
              category: 'Cultural',
              price: 50,
              duration: '4 hours'),
          _experience(
              id: 2,
              slug: 'newari-food-crawl',
              title: 'Newari Food Crawl Through Patan',
              city: 'Lalitpur',
              category: 'Food Tour',
              price: 42,
              duration: '3 hours',
              rating: 4.9,
              reviews: 118),
          _experience(
              id: 3,
              slug: 'sunday-momo-workshop',
              title: 'Sunday Momo Workshop',
              city: 'Kathmandu',
              category: 'Cooking Class',
              price: 35,
              duration: '2.5 hours',
              rating: 4.7,
              reviews: 64),
          _experience(
              id: 4,
              slug: 'sarangkot-sunrise-trek',
              title: 'Sarangkot Sunrise Trek',
              city: 'Pokhara',
              category: 'Outdoor',
              price: 60,
              duration: '6 hours',
              rating: 4.9,
              reviews: 210,
              spots: 4),
          _experience(
              id: 5,
              slug: 'chitwan-grassland-walk',
              title: 'Chitwan Grassland Walk',
              city: 'Bharatpur',
              category: 'Outdoor',
              price: 55,
              duration: '5 hours',
              rating: null,
              reviews: null),
          _experience(
              id: 6,
              slug: 'singing-bowl-session',
              title: 'Singing Bowl Sound Session',
              city: 'Kathmandu',
              category: 'Wellness',
              price: 28,
              duration: '1.5 hours',
              rating: 4.6,
              reviews: 31),
        ],
      '/guides' => [
          _host(name: 'Ram Bahadur'),
          _host(id: 2, name: 'Aarati Shrestha', role: 'Food guide'),
          _host(id: 3, name: 'Mingma Sherpa', role: 'Trek leader'),
          _host(id: 4, name: 'Sunita Thapa', role: 'Wellness host'),
        ],
      '/updates' => const [
          {
            'id': 1,
            'update_type': 'capacity',
            'message': 'Two seats left on Saturday’s Patan food walk.',
            'guide_name': 'Aarati Shrestha',
            'current_capacity': 8,
            'max_capacity': 10,
            'created_at': '2026-10-30T06:00:00Z',
            'cities': ['Lalitpur'],
          },
          {
            'id': 2,
            'update_type': 'schedule',
            'message': 'Sunrise trek moves to 4:30am pickup for the season.',
            'guide_name': 'Mingma Sherpa',
            'event_date': '2026-11-02T00:00:00Z',
            'created_at': '2026-10-29T06:00:00Z',
            'cities': ['Pokhara'],
          },
        ],
      '/profile/bookmarks' => const [],
      '/profile/photos/upload' => const {'url': '/uploads/11/avatar.png'},
      '/bookings/' => [
          _booking(
              id: 41,
              title: 'Sarangkot Sunrise Trek',
              status: 'upcoming',
              city: 'Pokhara'),
          _booking(
              id: 42,
              title: 'Bhaktapur Heritage Walk',
              status: 'completed',
              city: 'Bhaktapur',
              date: '2026-09-14T00:00:00Z',
              price: 100),
          _booking(
              id: 43,
              title: 'Newari Food Crawl Through Patan',
              status: 'cancelled',
              city: 'Lalitpur',
              date: '2026-08-02T00:00:00Z'),
        ],
      '/conversations' => const [
          {
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
              'body': 'Gate opens at 4am — I will meet you at the trailhead.',
              'sender_id': 5,
              'created_at': '2026-10-30T08:00:00Z',
            },
            'unread_count': 2,
            'created_at': '2026-10-20T08:00:00Z',
          },
          {
            'id': 8,
            'peer': {
              'id': 6,
              'firstName': 'Aarati',
              'lastName': 'Shrestha',
              'avatarUrl': null,
              'role': 'guide',
            },
            'last_message': {
              'id': 9,
              'body': 'Thanks for booking — see you on Saturday!',
              'sender_id': 6,
              'created_at': '2026-10-28T08:00:00Z',
            },
            'unread_count': 0,
            'created_at': '2026-10-18T08:00:00Z',
          },
        ],
      '/guide/dashboard' => {
          'stats': const {
            'listings': 2,
            'upcoming_bookings': 3,
            'total_guests': 9,
            'total_capacity': 22,
            'booked_capacity': 12,
            'available_spots': 10,
          },
          // The dashboard carries its own listings; an empty list next to a
          // "2 listings" stat would capture a state no real account can be in.
          'listings': const [
            {
              'id': 61,
              'title': 'Sarangkot Sunrise Trek',
              'category': 'trekking',
              'city': 'Pokhara',
              'duration': '6 hours',
              'difficulty': 'Moderate',
              'price': 60,
              'max_guests': 12,
              'booked_guests': 5,
              'available_spots': 7,
              'occupancy_pct': 42,
              'is_active': true,
            },
            {
              'id': 62,
              'title': 'Patan Food Crawl',
              'category': 'tour',
              'city': 'Lalitpur',
              'duration': '3 hours',
              'difficulty': 'Easy',
              'price': 42,
              'max_guests': 10,
              'booked_guests': 7,
              'available_spots': 3,
              'occupancy_pct': 70,
              'is_active': false,
            },
          ],
        },
      '/guide/bookings' => const [
          {
            'id': 51,
            'experience_title': 'Sarangkot Sunrise Trek',
            'city': 'Pokhara',
            'date': '2026-11-03T00:00:00Z',
            'guests': 3,
            'price': 180,
            'status': 'upcoming',
            'traveler_name': 'Anisha Gurung',
          },
          {
            'id': 52,
            'experience_title': 'Patan Food Crawl',
            'city': 'Lalitpur',
            'date': '2026-11-06T00:00:00Z',
            'guests': 2,
            'price': 84,
            'status': 'accepted',
            'traveler_name': 'Tom Becker',
          },
        ],
      '/guide/listings' => const [
          {
            'id': 61,
            'title': 'Sarangkot Sunrise Trek',
            'category': 'trekking',
            'city': 'Pokhara',
            'description': 'Pre-dawn climb with tea at the ridge.',
            'duration': '6 hours',
            'difficulty': 'Moderate',
            'price': 60,
            'max_guests': 12,
            'booked_guests': 5,
            'available_spots': 7,
            'occupancy_pct': 42,
            'is_active': true,
            'public_slug': 'listing-sarangkot-sunrise-trek',
          },
          {
            'id': 62,
            'title': 'Patan Food Crawl',
            'category': 'tour',
            'city': 'Lalitpur',
            'description': 'Six stops, all family kitchens.',
            'duration': '3 hours',
            'difficulty': 'Easy',
            'price': 42,
            'max_guests': 10,
            'booked_guests': 7,
            'available_spots': 3,
            'occupancy_pct': 70,
            'is_active': false,
            'public_slug': 'listing-patan-food-crawl',
          },
        ],
      '/guide/status' => const [
          {
            'id': 71,
            'update_type': 'capacity',
            'message': 'Two seats left on Saturday’s Patan food walk.',
            'current_capacity': 8,
            'max_capacity': 10,
            'is_active': true,
            'created_at': '2026-10-30T06:00:00Z',
          },
          {
            'id': 72,
            'update_type': 'announcement',
            'message': 'Monsoon is done — ridge trails are clear again.',
            'is_active': true,
            'created_at': '2026-10-27T06:00:00Z',
          },
        ],
      '/guide/onboarding' => const {
          'onboarding': {
            'display_name': 'Mingma Sherpa',
            'expertise_areas': ['Trekking', 'Culture'],
            'cities': ['Pokhara', 'Kathmandu'],
            'languages': ['Nepali', 'English', 'Sherpa'],
            'bio': 'Fifteen seasons on the Annapurna trails.',
            'years_experience': '15',
            'default_max_guests': 10,
            'onboarding_completed': true,
          },
          'completed': true,
        },
      _ => const {},
    };
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: data,
      statusCode: 200,
    );
  }
}

final _captureKey = GlobalKey();

/// Renders [screen] at 390×844 and writes `docs/screens/<name>.png`.
Future<void> _capture(
  WidgetTester tester,
  String name,
  Widget screen, {
  required AuthController Function() auth,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_CaptureApi()),
        authControllerProvider.overrideWith(auth),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        // A phone has a status bar; without this inset every capture clips its
        // own title and misrepresents the top of the screen.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 44),
            viewPadding: const EdgeInsets.only(top: 44),
          ),
          child: child!,
        ),
        home: RepaintBoundary(key: _captureKey, child: screen),
      ),
    ),
  );

  // Fixed pumps: skeletons and shimmer never settle, so a settle() would hang.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }

  // Encoding a frame needs the real event loop; inside the fake-async test
  // zone `toImage`/`toByteData` never complete.
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/screens/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('captured ${file.path}');
  });
}

Future<void> _loadFonts() async {
  for (final (family, path) in const [
    ('Inter', 'assets/fonts/Inter.ttf'),
    ('PlayfairDisplay', 'assets/fonts/PlayfairDisplay.ttf'),
  ]) {
    final bytes = File(path).readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  // Material icons ship as a font too. Without it every icon renders as a
  // tofu box, which would make every capture misleading.
  final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  final iconLoader = FontLoader('MaterialIcons')..addFont(Future.value(icons));
  await iconLoader.load();
}

void main() {
  setUpAll(() async {
    if (_capturing) await _loadFonts();
  });

  testWidgets('home', (tester) async {
    await _capture(tester, 'home', const HomeShell(), auth: _TravelerAuth.new);
  }, skip: !_capturing);

  testWidgets('explore', (tester) async {
    await _capture(tester, 'explore', const ExploreScreen(),
        auth: _TravelerAuth.new);
  }, skip: !_capturing);

  testWidgets('trips', (tester) async {
    await _capture(tester, 'trips', const TripsScreen(),
        auth: _TravelerAuth.new);
  }, skip: !_capturing);

  testWidgets('inbox', (tester) async {
    await _capture(tester, 'inbox', const InboxScreen(),
        auth: _TravelerAuth.new);
  }, skip: !_capturing);

  testWidgets('profile', (tester) async {
    await _capture(tester, 'profile', const ProfileScreen(),
        auth: _TravelerAuth.new);
  }, skip: !_capturing);

  testWidgets('profile-edit', (tester) async {
    await _capture(tester, 'profile-edit', const ProfileEditScreen(),
        auth: _TravelerAuth.new);
  }, skip: !_capturing);

  testWidgets('guide-workspace', (tester) async {
    await _capture(tester, 'guide-workspace', const GuideShell(),
        auth: _GuideAuth.new);
  }, skip: !_capturing);
}
