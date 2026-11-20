import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:guides_nepal/app/theme/app_theme.dart';
import 'package:guides_nepal/core/network/api_client.dart';
import 'package:guides_nepal/core/network/api_exception.dart';
import 'package:guides_nepal/core/storage/token_storage.dart';
import 'package:guides_nepal/features/auth/auth_repository.dart';
import 'package:guides_nepal/features/profile/profile_draft.dart';
import 'package:guides_nepal/features/profile/profile_edit_screen.dart';
import 'package:guides_nepal/l10n/app_strings.dart';
import 'package:guides_nepal/shared/models/app_user.dart';
import 'package:guides_nepal/shared/widgets/widgets.dart';

/// In-memory session storage — secure storage has no plugin in tests, and the
/// profile flow only reads it when the session is restored (never here).
class _MemoryTokenStorage extends TokenStorage {
  final Map<String, String> data = {};

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userJson,
  }) async {
    data['gn_access_token'] = accessToken;
    data['gn_refresh_token'] = refreshToken;
    data['gn_user_json'] = userJson;
  }

  @override
  Future<void> saveAccessToken(String token) async =>
      data['gn_access_token'] = token;

  @override
  Future<String?> readAccessToken() async => data['gn_access_token'];

  @override
  Future<String?> readRefreshToken() async => data['gn_refresh_token'];

  @override
  Future<String?> readUserJson() async => data['gn_user_json'];

  @override
  Future<void> clear() async => data.clear();
}

/// Signed in as a traveler whose profile already has a name and a phone.
class _SignedInAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(
          id: 11,
          email: 'traveler@guides-nepal.com',
          firstName: 'Anisha',
          lastName: 'Gurung',
          phone: '+977 98000 00000',
          bio: 'Slow traveler, fast eater.',
        ),
      );
}

/// The profile endpoints, backed by a mutable row so a PATCH is visible to the
/// GET that follows it.
class _FakeProfileApi extends ApiClient {
  _FakeProfileApi({this.patchError});

  final ApiException? patchError;

  /// The path the real endpoint returns: relative, resolved by
  /// `AppConfig.resolveMedia` wherever it is displayed.
  static const String uploadUrl = '/uploads/11/avatar.png';

  Map<String, dynamic> user = {
    'id': 11,
    'email': 'traveler@guides-nepal.com',
    'firstName': 'Anisha',
    'lastName': 'Gurung',
    'phone': '+977 98000 00000',
    'bio': 'Slow traveler, fast eater.',
    'avatarUrl': null,
  };

  Map<String, dynamic>? patched;
  bool uploadCalled = false;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    if (path == '/profile/me') {
      return Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        data: Map<String, dynamic>.of(user),
        statusCode: 200,
      );
    }
    throw ApiException(
        kind: ApiFailureKind.notFound, message: 'Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> patch(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    final error = patchError;
    if (error != null) throw error;
    if (path != '/profile/me') {
      throw ApiException(
          kind: ApiFailureKind.notFound, message: 'Unexpected PATCH $path');
    }
    final body = Map<String, dynamic>.from(data! as Map);
    patched = {...?patched, ...body};
    // The real server stores snake_case avatar_url and echoes camelCase.
    user = {
      ...user,
      if (body.containsKey('firstName')) 'firstName': body['firstName'],
      if (body.containsKey('lastName')) 'lastName': body['lastName'],
      if (body.containsKey('phone')) 'phone': body['phone'],
      if (body.containsKey('bio')) 'bio': body['bio'],
      if (body.containsKey('avatar_url')) 'avatarUrl': body['avatar_url'],
    };
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: {'status': 'ok'},
      statusCode: 200,
    );
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) async {
    if (path != '/profile/photos/upload') {
      throw ApiException(
          kind: ApiFailureKind.notFound, message: 'Unexpected POST $path');
    }
    uploadCalled = true;
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: {'url': uploadUrl},
      statusCode: 200,
    );
  }
}

/// Scrolls the form to the save button, then taps it.
Future<void> tapSave(WidgetTester tester) async {
  final save = find.widgetWithText(AppButton, AppStrings.save);
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  group('ProfileDraft', () {
    test('prefills from the session', () {
      const user = AppUser(
        id: 1,
        email: 'a@b.com',
        firstName: 'Anisha',
        lastName: 'Gurung',
        phone: '+977 1',
        bio: 'Hello',
      );
      final draft = ProfileDraft.fromUser(user);
      expect(draft.firstName, 'Anisha');
      expect(draft.lastName, 'Gurung');
      expect(draft.phone, '+977 1');
      expect(draft.bio, 'Hello');
    });

    test('needs at least one name', () {
      final errors =
          const ProfileDraft(firstName: '  ', lastName: '').validate();
      expect(errors['firstName'], AppStrings.nameRequired);
    });

    test('accepts a name without a last name', () {
      expect(const ProfileDraft(firstName: 'Anisha').isValid, isTrue);
    });

    test('rejects letters in a phone number', () {
      final errors =
          const ProfileDraft(firstName: 'A', phone: 'call me').validate();
      expect(errors['phone'], AppStrings.phoneInvalid);
    });

    test('accepts an international number with spaces and brackets', () {
      expect(
        const ProfileDraft(firstName: 'A', phone: '+977 (1) 555-0199').isValid,
        isTrue,
      );
    });

    test('caps the name and bio lengths', () {
      final longName = 'a' * (ProfileDraft.nameMaxLength + 1);
      final longBio = 'b' * (ProfileDraft.bioMaxLength + 1);
      expect(
        ProfileDraft(firstName: longName).validate()['firstName'],
        AppStrings.fieldTooLong,
      );
      expect(
        ProfileDraft(firstName: 'A', bio: longBio).validate()['bio'],
        AppStrings.fieldTooLong,
      );
    });

    test('sends trimmed values, including empty ones so fields can be cleared',
        () {
      final json = const ProfileDraft(
        firstName: ' Anisha ',
        lastName: ' Gurung ',
        phone: '',
        bio: ' Hi ',
      ).toJson();
      expect(json, {
        'firstName': 'Anisha',
        'lastName': 'Gurung',
        'phone': '',
        'bio': 'Hi',
      });
    });
  });

  group('profile contract', () {
    test('PATCH sends avatar_url, not the response-side camelCase', () async {
      final api = _FakeProfileApi();
      final repo = AuthRepository(api, _MemoryTokenStorage());

      final user = await repo.updateProfile(
        firstName: 'Anisha',
        avatarUrl: '/uploads/11/avatar.png',
      );

      expect(api.patched?['firstName'], 'Anisha');
      expect(api.patched?.containsKey('avatar_url'), isTrue,
          reason: 'the server ignores unknown keys, so a camelCase avatar '
              'would silently never save');
      expect(api.patched?.containsKey('avatarUrl'), isFalse);
      expect(user.avatarUrl, '/uploads/11/avatar.png');
    });

    test('upload posts multipart bytes and returns the stored path', () async {
      final api = _FakeProfileApi();
      final repo = AuthRepository(api, _MemoryTokenStorage());

      final url = await repo.uploadAvatar(
        bytes: const [1, 2, 3, 4],
        filename: 'me.png',
        contentType: 'image/png',
      );

      expect(api.uploadCalled, isTrue);
      expect(url, '/uploads/11/avatar.png');
    });
  });

  group('ProfileEditScreen', () {
    late _FakeProfileApi api;

    /// A phone-shaped viewport: at the 800×600 default the save button sits
    /// below the fold and a tap would silently miss it.
    Future<void> pump(WidgetTester tester,
        {_FakeProfileApi? apiOverride}) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      addTearDown(tester.view.reset);
      api = apiOverride ?? _FakeProfileApi();
      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Scaffold(body: Text('profile-tab')),
          ),
          GoRoute(
            path: '/profile/edit',
            builder: (_, __) => const ProfileEditScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            tokenStorageProvider.overrideWithValue(_MemoryTokenStorage()),
            authControllerProvider.overrideWith(_SignedInAuth.new),
          ],
          child:
              MaterialApp.router(routerConfig: router, theme: AppTheme.light),
        ),
      );
      await tester.pumpAndSettle();
      // Pushed, the way the Profile tab opens it — so save can pop back.
      router.push('/profile/edit');
      await tester.pumpAndSettle();
    }

    testWidgets('prefills the session identity', (tester) async {
      await pump(tester);

      expect(find.text('Anisha'), findsOneWidget);
      expect(find.text('Gurung'), findsOneWidget);
      expect(find.text('+977 98000 00000'), findsOneWidget);
      expect(find.text('Slow traveler, fast eater.'), findsOneWidget);
    });

    testWidgets('saving sends the edited values and pops', (tester) async {
      await pump(tester);

      await tester.enterText(
          find.widgetWithText(AppTextField, AppStrings.firstNameLabel), 'Asha');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(api.patched?['firstName'], 'Asha');
      expect(api.patched?['lastName'], 'Gurung');
      expect(find.text(AppStrings.profileSaved), findsOneWidget);
      expect(find.text('profile-tab'), findsOneWidget, reason: 'screen pops');
    });

    testWidgets('an empty name blocks the request and explains why',
        (tester) async {
      await pump(tester);

      await tester.enterText(
          find.widgetWithText(AppTextField, AppStrings.firstNameLabel), '');
      await tester.enterText(
          find.widgetWithText(AppTextField, AppStrings.lastNameLabel), '');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(find.text(AppStrings.nameRequired), findsOneWidget);
      expect(api.patched, isNull, reason: 'nothing may leave the device');
      expect(find.text('profile-tab'), findsNothing);
    });

    testWidgets('a rejected save keeps the form and shows the reason',
        (tester) async {
      await pump(
        tester,
        apiOverride: _FakeProfileApi(
          patchError: ApiException(
            kind: ApiFailureKind.validation,
            message: 'Name is not allowed.',
          ),
        ),
      );

      await tapSave(tester);

      expect(find.text('Name is not allowed.'), findsOneWidget);
      expect(find.text('Anisha'), findsOneWidget, reason: 'form is intact');
    });
  });
}
