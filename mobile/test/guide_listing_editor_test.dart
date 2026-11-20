import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/core/network/api_exception.dart';
import 'package:guides_nepal/features/auth/auth_controller.dart';
import 'package:guides_nepal/features/guide_tools/guide_models.dart';
import 'package:guides_nepal/features/guide_tools/guide_repository.dart';
import 'package:guides_nepal/features/guide_tools/guide_shell.dart';
import 'package:guides_nepal/features/guide_tools/listing_editor_screen.dart';
import 'package:guides_nepal/shared/models/app_user.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

class _GuideAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 2, email: 'guide@example.com', role: 'guide'),
      );
}

Map<String, dynamic> _listingJson({
  int id = 3,
  String title = 'Sunrise hike to Sarangkot',
  String category = 'trekking',
  String city = 'Pokhara',
  String? area = 'Lakeside',
  String description = 'An easy pre-dawn walk to the ridge above the lake.',
  String duration = '4 hours',
  String difficulty = 'Moderate',
  double price = 45,
  int maxGuests = 8,
  int bookedGuests = 2,
  bool isActive = true,
  String? heroImage,
}) =>
    {
      'id': id,
      'title': title,
      'hero_image': heroImage,
      'category': category,
      'city': city,
      'area': area,
      'description': description,
      'itinerary': null,
      'meeting_point': 'Lakeside clock tower',
      'duration': duration,
      'difficulty': difficulty,
      'price': price,
      'max_guests': maxGuests,
      'is_active': isActive,
      'booked_guests': bookedGuests,
      'available_spots': maxGuests - bookedGuests,
      'occupancy_pct': ((bookedGuests / maxGuests) * 100).round(),
    };

/// Scripted guide API: holds the server-side listings and applies the
/// create / patch / delete payloads, so the editor and cards are exercised
/// against the real `GuideRepository` and `GuideListing.fromJson`.
class _FakeGuideApi extends ApiClient {
  _FakeGuideApi(this.listings);

  final List<Map<String, dynamic>> listings;

  final List<(String method, String path, Object? data)> calls = [];
  ApiException? failNextWrite;

  /// Payload for `GET /guide/onboarding`; `null` means the guide has not
  /// onboarded yet.
  Map<String, dynamic>? onboarding;

  List<Object?> get writeBodies =>
      [for (final c in calls) if (c.$1 != 'GET') c.$3];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    calls.add(('GET', path, null));
    if (path == '/guide/listings') {
      return _ok(listings.map((l) => Map<String, dynamic>.of(l)).toList());
    }
    if (path == '/guide/onboarding') {
      return _ok({
        'onboarding': onboarding,
        'completed': onboarding != null,
      });
    }
    if (path == '/guide/dashboard') {
      return _ok({
        'stats': {
          'listings': listings.length,
          'upcoming_bookings': 0,
          'total_guests': 0,
          'total_capacity': 8,
          'booked_capacity': 2,
          'available_spots': 6,
        },
        'listings': listings,
        'recent_status': const [],
      });
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
    _maybeFail();
    final photo = RegExp(r'^/guide/listings/(\d+)/photo$').firstMatch(path);
    if (photo != null) {
      final id = int.parse(photo.group(1)!);
      final index = listings.indexWhere((l) => l['id'] == id);
      if (index == -1) {
        throw ApiException(
            kind: ApiFailureKind.notFound, message: 'Listing not found');
      }
      final updated = {
        ...listings[index],
        'hero_image': '/uploads/listings/$id/uploaded.png',
      };
      listings[index] = updated;
      return _ok(Map<String, dynamic>.of(updated));
    }
    if (path != '/guide/listings') {
      throw ApiException(
          kind: ApiFailureKind.notFound, message: 'Unexpected POST $path');
    }
    final payload = (data as Map).cast<String, dynamic>();
    final created = {
      ...payload,
      'id': 99,
      'booked_guests': 0,
      'available_spots': payload['max_guests'],
      'occupancy_pct': 0,
    };
    listings.insert(0, created);
    return _ok(Map<String, dynamic>.of(created));
  }

  @override
  Future<Response<dynamic>> patch(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    calls.add(('PATCH', path, data));
    _maybeFail();
    final match = RegExp(r'^/guide/listings/(\d+)$').firstMatch(path);
    if (match == null) {
      throw ApiException(
          kind: ApiFailureKind.notFound, message: 'Unexpected PATCH $path');
    }
    final id = int.parse(match.group(1)!);
    final index = listings.indexWhere((l) => l['id'] == id);
    if (index == -1) {
      throw ApiException(
          kind: ApiFailureKind.notFound, message: 'Listing not found');
    }
    final merged = {
      ...listings[index],
      ...(data as Map).cast<String, dynamic>(),
    };
    merged['available_spots'] =
        (merged['max_guests'] as int) - (merged['booked_guests'] as int);
    listings[index] = merged;
    return _ok(Map<String, dynamic>.of(merged));
  }

  @override
  Future<Response<dynamic>> delete(
    String path, {
    CancelToken? cancelToken,
  }) async {
    calls.add(('DELETE', path, null));
    _maybeFail();
    final match = RegExp(r'^/guide/listings/(\d+)$').firstMatch(path);
    final id = int.parse(match?.group(1) ?? '0');
    listings.removeWhere((l) => l['id'] == id);
    return _ok({'status': 'ok'});
  }

  void _maybeFail() {
    final error = failNextWrite;
    if (error != null) {
      failNextWrite = null;
      throw error;
    }
  }

  Response<dynamic> _ok(Object data) =>
      Response(data: data, requestOptions: RequestOptions(path: '/'));
}

void main() {
  group('onboarding envelope', () {
    test('reads the profile nested under `onboarding`', () async {
      final fake = _FakeGuideApi([]);
      fake.onboarding = {
        'guide_user_id': 2,
        'display_name': 'Pemba Sherpa',
        'expertise_areas': ['trekking'],
        'cities': ['Pokhara'],
        'languages': ['Nepali', 'English'],
        'bio': 'Fifteen seasons on the Annapurna trails.',
        'years_experience': '15',
        'default_max_guests': 12,
        'onboarding_completed': true,
      };

      final profile =
          await GuideRepository(fake).fetchOnboarding();

      // The envelope itself must not be parsed as the profile.
      expect(profile.displayName, 'Pemba Sherpa');
      expect(profile.cities, ['Pokhara']);
      expect(profile.languages, ['Nepali', 'English']);
      expect(profile.defaultMaxGuests, 12);
      expect(profile.onboardingCompleted, isTrue);
    });

    test('a guide who never onboarded gets an empty profile', () async {
      final fake = _FakeGuideApi([]);

      final profile = await GuideRepository(fake).fetchOnboarding();

      expect(profile.displayName, isNull);
      expect(profile.cities, isEmpty);
      expect(profile.onboardingCompleted, isFalse);
    });
  });

  group('ListingDraft validation mirrors the server schema', () {
    ListingDraft valid({
      String title = 'Sunrise hike',
      String city = 'Pokhara',
      String area = '',
      String description = 'A pre-dawn walk to the ridge above the lake.',
      String duration = '4 hours',
      String difficulty = 'Moderate',
      String priceText = '45',
      String maxGuestsText = '8',
    }) =>
        ListingDraft(
          title: title,
          city: city,
          area: area,
          description: description,
          duration: duration,
          difficulty: difficulty,
          priceText: priceText,
          maxGuestsText: maxGuestsText,
        );

    test('a complete draft passes and serializes to snake_case', () {
      final draft = valid();
      expect(draft.validate(), isEmpty);

      final json = draft.toJson();
      expect(json['title'], 'Sunrise hike');
      expect(json['category'], 'tour');
      expect(json['duration'], '4 hours');
      expect(json['price'], 45);
      expect(json['max_guests'], 8);
      expect(json['is_active'], isTrue);
      // Empty optional text becomes null, not an empty string.
      expect(json.containsKey('area'), isTrue);
      expect(json['area'], isNull);
      expect(json['meeting_point'], isNull);
    });

    test('blank draft reports every required field once', () {
      final errors = const ListingDraft().validate();
      expect(
        errors.keys,
        containsAll([
          'title',
          'city',
          'description',
          'duration',
          'price',
        ]),
      );
      expect(errors['title'], 'Give your experience a title.');
      // A new listing starts at the default group size, which is valid.
      expect(const ListingDraft().maxGuestsText, '10');
      expect(errors.containsKey('maxGuests'), isFalse);
    });

    test('respects the server length and range limits', () {
      expect(valid().validate(), isEmpty, reason: 'baseline is valid');

      expect(
        valid(title: 'ab').validate()['title'],
        'Use at least 3 characters.',
      );
      expect(
        ListingDraft(title: 'x' * 161).validate()['title'],
        'Keep the title under 160 characters.',
      );
      expect(
        valid(description: 'x' * 9).validate()['description'],
        'Use at least 10 characters.',
      );
      expect(
        valid(area: 'x' * 161).validate()['area'],
        'Keep the area under 160 characters.',
      );
      expect(
        valid(maxGuestsText: '0').validate()['maxGuests'],
        'At least one guest.',
      );
      expect(
        valid(maxGuestsText: '101').validate()['maxGuests'],
        'Up to 100 guests.',
      );
      expect(
        valid(priceText: '-5').validate()['price'],
        'Price cannot be negative.',
      );
      expect(
        valid(priceText: 'free').validate()['price'],
        'Enter a price, e.g. 50.',
      );
    });

    test('round-trips a listing into editable text', () {
      final listing = GuideListing.fromJson(_listingJson());
      final draft = ListingDraft.fromListing(listing);

      expect(draft.title, 'Sunrise hike to Sarangkot');
      expect(draft.priceText, '45');
      expect(draft.maxGuestsText, '8');
      expect(draft.isActive, isTrue);
      expect(draft.validate(), isEmpty);
    });
  });

  group('listing photo', () {
    test('upload sends a multipart file, not JSON', () async {
      final fake = _FakeGuideApi([_listingJson()]);

      final listing = await GuideRepository(fake).uploadListingPhoto(
        3,
        bytes: const [1, 2, 3, 4],
        filename: 'ridge.png',
        contentType: 'image/png',
      );

      final call = fake.calls.singleWhere((c) => c.$1 == 'POST');
      expect(call.$2, '/guide/listings/3/photo');
      final form = call.$3;
      expect(form, isA<FormData>());
      final part = (form as FormData).files.single;
      expect(part.key, 'file');
      expect(part.value.filename, 'ridge.png');
      // Without this the server sees application/octet-stream and refuses it.
      expect(part.value.contentType?.mimeType, 'image/png');
      expect(listing.heroImage, '/uploads/listings/3/uploaded.png');
    });

    test('clearing the photo patches an explicit null', () async {
      final fake = _FakeGuideApi(
        [_listingJson(heroImage: '/uploads/listings/3/old.png')],
      );

      final listing = await GuideRepository(fake).removeListingPhoto(3);

      final call = fake.calls.singleWhere((c) => c.$1 == 'PATCH');
      expect(call.$2, '/guide/listings/3');
      expect((call.$3! as Map)['hero_image'], isNull);
      expect(listing.heroImage, isNull);
    });
  });

  group('listing editor', () {
    late _FakeGuideApi fake;
    late bool? popResult;
    late bool opened;

    setUp(() {
      fake = _FakeGuideApi([_listingJson()]);
      popResult = null;
      opened = false;
    });

    /// Hosts the editor behind a real `Navigator.push`, so the pop-result
    /// contract the guide workspace relies on is exercised too.
    Future<void> pumpEditor(
      WidgetTester tester, {
      int? listingId,
      Size surface = const Size(900, 2600),
    }) async {
      tester.view.physicalSize = surface;
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
                      opened = true;
                      popResult = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => ListingEditorScreen(
                            listingId: listingId,
                          ),
                        ),
                      );
                    },
                    child: const Text('open-editor'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-editor'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    }

    Future<void> type(WidgetTester tester, String key, String text) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
      await tester.pump();
    }

    Future<void> fillValidListing(WidgetTester tester) async {
      await type(tester, 'listing-title', 'Sunrise hike to Sarangkot');
      await type(tester, 'listing-city', 'Pokhara');
      await type(tester, 'listing-duration', '4 hours');
      await type(tester, 'listing-price', '45');
      await type(tester, 'listing-max-guests', '8');
      await type(tester, 'listing-description',
          'An easy pre-dawn walk to the ridge above the lake.');
    }

    Future<void> tapSave(WidgetTester tester, String label) async {
      final button = find.widgetWithText(AppButton, label);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('creating a listing posts the payload and pops with true',
        (tester) async {
      await pumpEditor(tester);
      expect(find.text('New listing'), findsOneWidget);

      await fillValidListing(tester);
      await tester.tap(find.widgetWithText(AppFilterChip, 'Trekking'));
      await tester.pump();
      await tapSave(tester, 'Save listing');

      expect(fake.calls.where((c) => c.$1 == 'POST').map((c) => c.$2),
          ['/guide/listings']);
      final body = fake.writeBodies.single! as Map<String, dynamic>;
      expect(body['title'], 'Sunrise hike to Sarangkot');
      expect(body['category'], 'trekking');
      expect(body['city'], 'Pokhara');
      expect(body['duration'], '4 hours');
      expect(body['difficulty'], 'Easy');
      expect(body['price'], 45);
      expect(body['max_guests'], 8);
      expect(body['is_active'], isTrue);

      // The editor closes and reports the change to its caller.
      expect(find.text('open-editor'), findsOneWidget);
      expect(popResult, isTrue);
      expect(fake.listings, hasLength(2));
    });

    testWidgets('an incomplete draft is blocked before any request',
        (tester) async {
      await pumpEditor(tester);

      await tapSave(tester, 'Save listing');

      expect(fake.calls.where((c) => c.$1 != 'GET'), isEmpty);
      expect(find.text('Give your experience a title.'), findsOneWidget);
      expect(find.text('Describe the experience.'), findsOneWidget);
      expect(find.text('Which city is this in?'), findsOneWidget);
      // Still on the editor — nothing was submitted.
      expect(find.text('New listing'), findsOneWidget);
      expect(popResult, isNull);
    });

    testWidgets('editing prefills the listing and patches the changes',
        (tester) async {
      await pumpEditor(tester, listingId: 3);

      expect(find.text('Edit listing'), findsOneWidget);
      final title = tester.widget<AppTextField>(
        find.byKey(const ValueKey('listing-title')),
      );
      expect(title.controller.text, 'Sunrise hike to Sarangkot');
      final price = tester.widget<AppTextField>(
        find.byKey(const ValueKey('listing-price')),
      );
      expect(price.controller.text, '45');

      await type(tester, 'listing-title', 'Sunrise hike to Sarangkot ridge');
      await tapSave(tester, 'Save changes');

      final patch = fake.calls.singleWhere((c) => c.$1 == 'PATCH');
      expect(patch.$2, '/guide/listings/3');
      expect((patch.$3! as Map)['title'], 'Sunrise hike to Sarangkot ridge');
      expect(fake.listings.single['title'], 'Sunrise hike to Sarangkot ridge');
      expect(popResult, isTrue);
    });

    testWidgets('a stored photo can be removed without saving the form',
        (tester) async {
      fake.listings[0]['hero_image'] = '/uploads/listings/3/ridge.png';
      await pumpEditor(tester, listingId: 3);

      expect(find.text('Change photo'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();

      final patch = fake.calls.singleWhere((c) => c.$1 == 'PATCH');
      expect(patch.$2, '/guide/listings/3');
      expect((patch.$3! as Map)['hero_image'], isNull);
      expect(fake.listings.single['hero_image'], isNull);
      // The field now offers to add one again.
      expect(find.text('Add photo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('the visibility switch pauses the listing on save',
        (tester) async {
      await pumpEditor(tester, listingId: 3);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tapSave(tester, 'Save changes');

      final patch = fake.calls.singleWhere((c) => c.$1 == 'PATCH');
      expect((patch.$3! as Map)['is_active'], isFalse);
      expect(fake.listings.single['is_active'], isFalse);
    });

    testWidgets('deleting asks first, then removes the listing',
        (tester) async {
      await pumpEditor(tester, listingId: 3);

      final deleteButton = find.widgetWithText(AppButton, 'Delete listing');
      await tester.ensureVisible(deleteButton);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.text('Delete this listing?'), findsOneWidget);
      expect(fake.calls.where((c) => c.$1 == 'DELETE'), isEmpty);

      // Backing out keeps everything.
      await tester.tap(find.widgetWithText(TextButton, 'Keep listing'));
      await tester.pumpAndSettle();
      expect(fake.calls.where((c) => c.$1 == 'DELETE'), isEmpty);
      expect(fake.listings, hasLength(1));

      await tester.ensureVisible(deleteButton);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(fake.calls.singleWhere((c) => c.$1 == 'DELETE').$2,
          '/guide/listings/3');
      expect(fake.listings, isEmpty);
      expect(popResult, isTrue);
    });

    testWidgets('a server rejection stays on the form with the message shown',
        (tester) async {
      await pumpEditor(tester, listingId: 3);
      fake.failNextWrite = ApiException(
        kind: ApiFailureKind.validation,
        statusCode: 422,
        message: 'max_guests cannot be below booked guests',
      );

      await tapSave(tester, 'Save changes');

      expect(find.text('max_guests cannot be below booked guests'),
          findsOneWidget);
      // Nothing popped: the guide can fix the value and retry.
      expect(find.text('Edit listing'), findsOneWidget);
      expect(popResult, isNull);

      // Let the snackbar clear so it cannot swallow the retry tap.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tapSave(tester, 'Save changes');
      expect(popResult, isTrue);
    });

    testWidgets('a missing listing explains itself instead of a blank form',
        (tester) async {
      await pumpEditor(tester, listingId: 404);

      expect(find.text('This listing is no longer available.'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Save changes'), findsNothing);
    });
  });

  group('listings tab', () {
    late _FakeGuideApi fake;

    Future<void> pumpShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      fake = _FakeGuideApi([_listingJson()]);
      final router = GoRouter(
        initialLocation: '/guide',
        routes: [
          GoRoute(path: '/guide', builder: (_, __) => const GuideShell()),
          GoRoute(
            path: '/guide/listing/new',
            builder: (_, __) => const ListingEditorScreen(),
          ),
          GoRoute(
            path: '/guide/listing/:id',
            builder: (_, state) => ListingEditorScreen(
              listingId: int.tryParse(state.pathParameters['id'] ?? ''),
            ),
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
      await tester.tap(find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Listings'),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('pause hides the listing and the card shows it paused',
        (tester) async {
      await pumpShell(tester);
      expect(find.text('Paused'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Pause'));
      await tester.pumpAndSettle();

      final patch = fake.calls.singleWhere((c) => c.$1 == 'PATCH');
      expect(patch.$2, '/guide/listings/3');
      expect((patch.$3! as Map)['is_active'], isFalse);
      // The card reloads from the server and reflects the new state.
      expect(find.text('Paused'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Resume'), findsOneWidget);
    });

    testWidgets('edit opens the editor for that listing', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit listing'), findsOneWidget);
      final title = tester.widget<AppTextField>(
        find.byKey(const ValueKey('listing-title')),
      );
      expect(title.controller.text, 'Sunrise hike to Sarangkot');
    });

    testWidgets('an empty workspace offers the create action', (tester) async {
      fake = _FakeGuideApi([]);
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/guide',
        routes: [
          GoRoute(path: '/guide', builder: (_, __) => const GuideShell()),
          GoRoute(
            path: '/guide/listing/new',
            builder: (_, __) => const ListingEditorScreen(),
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
      await tester.tap(find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Listings'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No listings yet'), findsOneWidget);
      await tester.tap(
          find.widgetWithText(AppButton, 'Create a listing'));
      await tester.pumpAndSettle();
      expect(find.text('New listing'), findsOneWidget);
    });
  });
}
