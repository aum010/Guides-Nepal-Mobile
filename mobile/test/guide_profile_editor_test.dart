import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/core/network/api_exception.dart';
import 'package:guides_nepal/features/auth/auth_controller.dart';
import 'package:guides_nepal/features/guide_tools/guide_models.dart';
import 'package:guides_nepal/features/guide_tools/guide_profile_editor_screen.dart';
import 'package:guides_nepal/features/guide_tools/guide_shell.dart';
import 'package:guides_nepal/shared/models/app_user.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

class _GuideAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(id: 2, email: 'guide@example.com', role: 'guide'),
      );
}

Map<String, dynamic> _profileJson({
  String? displayName = 'Pemba Sherpa',
  List<String> expertise = const ['trekking'],
  List<String> cities = const ['Pokhara'],
  List<String> languages = const ['Nepali', 'English'],
  String? bio = 'Fifteen seasons on the Annapurna trails and every tea house '
      'between here and Poon Hill.',
  String? years = '15',
  int maxGuests = 12,
  bool completed = true,
}) =>
    {
      'guide_user_id': 2,
      'display_name': displayName,
      'expertise_areas': expertise,
      'cities': cities,
      'languages': languages,
      'bio': bio,
      'years_experience': years,
      'default_max_guests': maxGuests,
      'onboarding_completed': completed,
    };

/// Scripted guide API that actually stores the onboarding profile, so the
/// editor is exercised against the real `GuideRepository` and
/// `GuideProfileDraft` rather than a stub.
class _FakeGuideApi extends ApiClient {
  _FakeGuideApi({this.profile});

  Map<String, dynamic>? profile;
  final List<(String method, String path, Object? data)> calls = [];
  ApiException? failNextWrite;

  /// Fails `GET /guide/onboarding` only, so the dashboard still loads.
  ApiException? failOnboardingRead;

  Iterable<Object?> get writeBodies =>
      [for (final c in calls) if (c.$1 != 'GET') c.$3];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    calls.add(('GET', path, null));
    switch (path) {
      case '/guide/onboarding':
        final readError = failOnboardingRead;
        if (readError != null) throw readError;
        return _ok({
          'onboarding': profile,
          'completed': profile?['onboarding_completed'] ?? false,
        });
      case '/guide/listings':
        return _ok(const []);
      case '/guide/dashboard':
        return _ok({
          'stats': {
            'listings': 0,
            'upcoming_bookings': 0,
            'total_guests': 0,
            'total_capacity': 0,
            'booked_capacity': 0,
            'available_spots': 0,
          },
          'listings': const [],
          'recent_status': const [],
        });
    }
    throw ApiException(
        kind: ApiFailureKind.notFound, message: 'Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> put(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    calls.add(('PUT', path, data));
    final error = failNextWrite;
    if (error != null) {
      failNextWrite = null;
      throw error;
    }
    if (path != '/guide/onboarding') {
      throw ApiException(
          kind: ApiFailureKind.notFound, message: 'Unexpected PUT $path');
    }
    final payload = (data as Map).cast<String, dynamic>();
    profile = {'guide_user_id': 2, ...payload};
    return _ok({'onboarding': profile});
  }

  Response<dynamic> _ok(Object data) =>
      Response(data: data, requestOptions: RequestOptions(path: '/'));
}

void main() {
  group('GuideProfileDraft mirrors the server schema', () {
    test('an empty draft is a saveable draft, not a complete profile', () {
      const draft = GuideProfileDraft();

      expect(draft.validate(), isEmpty, reason: 'drafts may be partial');
      expect(draft.defaultMaxGuestsText, '10');
      expect(
        draft.missingForCompletion(),
        [
          'a display name',
          'an expertise area',
          'a city',
          'a language',
          'a short bio',
        ],
      );
    });

    test('claiming completion without the details is rejected locally', () {
      final errors = const GuideProfileDraft(onboardingCompleted: true)
          .validate();

      expect(errors['displayName'], 'Add the name travelers will see.');
      expect(errors['expertiseAreas'], 'Pick at least one expertise area.');
      expect(errors['cities'], 'Pick at least one city.');
      expect(errors['languages'], 'Pick at least one language.');
      expect(errors['bio'], 'Tell travelers about yourself.');
      // The default group size is already valid.
      expect(errors.containsKey('defaultMaxGuests'), isFalse);
    });

    test('respects the server length and range limits', () {
      GuideProfileDraft draft({
        String name = 'Pemba Sherpa',
        String bio = 'Fifteen seasons on the Annapurna trails.',
        String years = '15',
        String guests = '12',
      }) =>
          GuideProfileDraft(
            displayName: name,
            bio: bio,
            yearsExperience: years,
            defaultMaxGuestsText: guests,
          );

      expect(draft().validate(), isEmpty, reason: 'baseline is valid');
      expect(
        draft(name: 'x' * 161).validate()['displayName'],
        'Keep the name under 160 characters.',
      );
      expect(
        draft(bio: 'x' * 5001).validate()['bio'],
        'Keep the bio under 5000 characters.',
      );
      expect(
        draft(years: 'x' * 41).validate()['yearsExperience'],
        'Keep this under 40 characters.',
      );
      expect(draft(guests: '0').validate()['defaultMaxGuests'],
          'At least one guest.');
      expect(draft(guests: '101').validate()['defaultMaxGuests'],
          'Up to 100 guests.');
      expect(draft(guests: 'ten').validate()['defaultMaxGuests'],
          'Enter a group size, e.g. 10.');
    });

    test('a complete profile passes and serializes to the server contract', () {
      final draft = GuideProfileDraft.fromProfile(
        GuideOnboarding.fromJson(_profileJson()),
      );

      expect(draft.validate(), isEmpty);
      expect(draft.missingForCompletion(), isEmpty);

      final json = draft.toProfile().toJson();
      expect(json['display_name'], 'Pemba Sherpa');
      expect(json['expertise_areas'], ['trekking']);
      expect(json['cities'], ['Pokhara']);
      expect(json['languages'], ['Nepali', 'English']);
      expect(json['years_experience'], '15');
      expect(json['default_max_guests'], 12);
      expect(json['onboarding_completed'], isTrue);
    });

    test('clearing a field sends null, not an empty string', () {
      final draft = GuideProfileDraft.fromProfile(
        GuideOnboarding.fromJson(
          _profileJson(displayName: null, bio: null, years: null),
        ),
      );

      final json = draft.toProfile().toJson();
      expect(json.containsKey('display_name'), isTrue);
      expect(json['display_name'], isNull);
      expect(json['bio'], isNull);
      expect(json['years_experience'], isNull);
    });
  });

  group('profile editor', () {
    late _FakeGuideApi fake;
    late bool? popResult;

    setUp(() {
      fake = _FakeGuideApi();
      popResult = null;
    });

    /// Hosts the editor behind a real `Navigator.push`, so the pop-result
    /// contract the guide workspace relies on is exercised too.
    Future<void> pumpEditor(WidgetTester tester, {bool open = true}) async {
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
                          builder: (_) => const GuideProfileEditorScreen(),
                        ),
                      );
                    },
                    child: const Text('open-profile'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (open) {
        await tester.tap(find.text('open-profile'));
        await tester.pumpAndSettle();
      }
    }

    Future<void> type(WidgetTester tester, String key, String text) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
      await tester.pump();
    }

    Future<void> tapSave(WidgetTester tester, String label) async {
      final button = find.widgetWithText(AppButton, label);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('a guide without a profile gets a blank, saveable draft',
        (tester) async {
      await pumpEditor(tester);

      final name = tester.widget<AppTextField>(
        find.byKey(const ValueKey('profile-display-name')),
      );
      expect(name.controller.text, '');
      expect(find.text('Save draft'), findsOneWidget);

      await tapSave(tester, 'Save draft');

      final body = fake.writeBodies.single! as Map<String, dynamic>;
      expect(body['display_name'], isNull);
      expect(body['onboarding_completed'], isFalse);
      expect(body['default_max_guests'], 10);
      expect(fake.calls.singleWhere((c) => c.$1 == 'PUT').$2,
          '/guide/onboarding');
      // Saved: the card behind the editor can refresh.
      expect(popResult, isTrue);
    });

    testWidgets('an existing profile prefills and saves the edited selection',
        (tester) async {
      fake.profile = _profileJson();
      await pumpEditor(tester);

      expect(find.text('Save profile'), findsOneWidget);
      final name = tester.widget<AppTextField>(
        find.byKey(const ValueKey('profile-display-name')),
      );
      expect(name.controller.text, 'Pemba Sherpa');
      final guests = tester.widget<AppTextField>(
        find.byKey(const ValueKey('profile-max-guests')),
      );
      expect(guests.controller.text, '12');

      // Drop one language, add another city.
      await tester.tap(find.widgetWithText(AppFilterChip, 'English'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppFilterChip, 'Kathmandu'));
      await tester.pump();
      await type(tester, 'profile-years', '16');
      await tapSave(tester, 'Save profile');

      final body = fake.writeBodies.single! as Map<String, dynamic>;
      expect(body['languages'], ['Nepali']);
      expect(body['cities'], ['Pokhara', 'Kathmandu']);
      expect(body['years_experience'], '16');
      expect(body['onboarding_completed'], isTrue);
      expect(popResult, isTrue);
      expect(fake.profile!['cities'], ['Pokhara', 'Kathmandu']);
    });

    testWidgets('marking a blank profile complete is blocked before any request',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byKey(const ValueKey('profile-complete')));
      await tester.pumpAndSettle();
      await tapSave(tester, 'Save profile');

      expect(fake.calls.where((c) => c.$1 == 'PUT'), isEmpty);
      expect(find.text('Add the name travelers will see.'), findsOneWidget);
      expect(find.text('Pick at least one expertise area.'), findsOneWidget);
      expect(find.text('Pick at least one city.'), findsOneWidget);
      expect(find.text('Pick at least one language.'), findsOneWidget);
      expect(find.text('Tell travelers about yourself.'), findsOneWidget);
      expect(find.text('Guide profile'), findsOneWidget);
      expect(popResult, isNull);
    });

    testWidgets('a server rejection keeps the form with its typed values',
        (tester) async {
      fake.profile = _profileJson();
      await pumpEditor(tester);
      fake.failNextWrite = ApiException(
        kind: ApiFailureKind.server,
        statusCode: 500,
        message: 'Guides Nepal is having trouble right now. Please try again.',
      );

      const edited = 'Updated bio that is easily long enough to pass.';
      await type(tester, 'profile-bio', edited);
      await tapSave(tester, 'Save profile');

      expect(
        find.text('Guides Nepal is having trouble right now. Please try again.'),
        findsOneWidget,
      );
      final bio = tester.widget<AppTextField>(
        find.byKey(const ValueKey('profile-bio')),
      );
      expect(bio.controller.text, edited);
      // Nothing popped, and the rejected payload did not reach the server.
      expect(popResult, isNull);
      expect(fake.calls.where((c) => c.$1 == 'PUT'), hasLength(1));
      expect(fake.profile!['bio'], isNot(edited));

      // Let the snackbar clear so it cannot swallow the retry tap.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tapSave(tester, 'Save profile');

      expect(popResult, isTrue);
      expect(fake.profile!['bio'], edited);
    });

    testWidgets('a failed load offers a retry instead of an empty form',
        (tester) async {
      fake.profile = _profileJson();
      fake.failOnboardingRead = ApiException(
        kind: ApiFailureKind.network,
        message: 'Could not reach Guides Nepal. Check your connection.',
      );
      await pumpEditor(tester);

      expect(
        find.text('Could not reach Guides Nepal. Check your connection.'),
        findsOneWidget,
      );
      // No form: an empty draft would overwrite the saved profile.
      expect(find.byKey(const ValueKey('profile-bio')), findsNothing);

      fake.failOnboardingRead = null;
      await tester.tap(find.widgetWithText(AppButton, 'Try again'));
      await tester.pumpAndSettle();

      final name = tester.widget<AppTextField>(
        find.byKey(const ValueKey('profile-display-name')),
      );
      expect(name.controller.text, 'Pemba Sherpa');
    });
  });

  group('workspace profile card', () {
    late _FakeGuideApi fake;

    Future<void> pumpShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/guide',
        routes: [
          GoRoute(path: '/guide', builder: (_, __) => const GuideShell()),
          GoRoute(
            path: '/guide/profile',
            builder: (_, __) => const GuideProfileEditorScreen(),
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
    }

    testWidgets('a new guide is prompted to finish the profile',
        (tester) async {
      fake = _FakeGuideApi();
      await pumpShell(tester);

      expect(find.text('Finish your guide profile'), findsOneWidget);
      expect(
        find.text('Add your details so your account is ready to host.'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Complete profile'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('profile-bio')), findsOneWidget);
    });

    testWidgets('a nearly complete profile names what is missing',
        (tester) async {
      fake = _FakeGuideApi(
        profile: _profileJson(cities: const [], completed: false),
      );
      await pumpShell(tester);

      expect(find.text('Add a city.'), findsOneWidget);
      expect(find.text('Finish your guide profile'), findsOneWidget);
    });

    testWidgets('a complete profile shows its summary instead of a prompt',
        (tester) async {
      fake = _FakeGuideApi(profile: _profileJson());
      await pumpShell(tester);

      expect(find.text('Profile complete'), findsOneWidget);
      expect(find.text('Pemba Sherpa · Pokhara'), findsOneWidget);
      expect(find.text('Finish your guide profile'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Edit'));
      await tester.pumpAndSettle();
      final name = tester.widget<AppTextField>(
        find.byKey(const ValueKey('profile-display-name')),
      );
      expect(name.controller.text, 'Pemba Sherpa');
    });

    testWidgets('a profile the server cannot load offers a retry',
        (tester) async {
      fake = _FakeGuideApi()
        ..failOnboardingRead = ApiException(
          kind: ApiFailureKind.network,
          message: 'Could not reach Guides Nepal. Check your connection.',
        );
      await pumpShell(tester);

      // The dashboard still renders; only the card reports the failure.
      expect(find.text('Your listings'), findsWidgets);
      expect(
        find.text('Could not reach Guides Nepal. Check your connection.'),
        findsOneWidget,
      );

      fake.failOnboardingRead = null;
      await tester.tap(find.widgetWithText(TextButton, 'Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Finish your guide profile'), findsOneWidget);
    });
  });
}
