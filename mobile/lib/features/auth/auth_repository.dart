import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/token_storage.dart';
import '../../shared/models/app_user.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final tokenStorageProvider =
    Provider<TokenStorage>((ref) => TokenStorage());

/// Authenticated session state.
enum AuthStatus { restoring, signedOut, authenticated }

class AuthState {
  const AuthState({required this.status, this.user});

  final AuthStatus status;
  final AppUser? user;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isGuide => user?.isGuide ?? false;

  AuthState copyWith({AuthStatus? status, AppUser? user}) => AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
      );
}

/// Registration/login/logout and profile editing against the verified
/// `/api/v1/auth` and `/api/v1/profile` contracts.
class AuthRepository {
  AuthRepository(this._client, this._storage);

  final ApiClient _client;
  final TokenStorage _storage;

  Future<AuthState> restoreSession() async {
    final token = await _storage.readAccessToken();
    final userJson = await _storage.readUserJson();
    if (token == null || token.isEmpty) {
      return const AuthState(status: AuthStatus.signedOut);
    }
    _client.authInterceptor.setToken(token);
    // Validate the cached session against the server.
    try {
      final me = await _client.get('/profile/me');
      final user = AppUser.fromJson(
        (me.data as Map).cast<String, dynamic>(),
      );
      return AuthState(status: AuthStatus.authenticated, user: user);
    } on ApiException catch (e) {
      if (e.kind == ApiFailureKind.unauthorized ||
          e.kind == ApiFailureKind.forbidden) {
        // Access tokens are short-lived; before giving up the session,
        // exchange the stored refresh token for a fresh pair. Only a
        // rejected/refresh token means a real sign-out.
        final refreshed = await _tryRefreshSession();
        if (refreshed != null) return refreshed;
        await _storage.clear();
        _client.authInterceptor.setToken(null);
        return const AuthState(status: AuthStatus.signedOut);
      }
      // Offline/unknown failure: fall back to the cached identity rather
      // than logging the user out spuriously. Protected calls will still
      // fail gracefully until connectivity returns.
      if (userJson != null) {
        try {
          final user = AppUser.fromJson(
            (jsonDecode(userJson) as Map).cast<String, dynamic>(),
          );
          return AuthState(status: AuthStatus.authenticated, user: user);
        } catch (_) {/* fall through */}
      }
      rethrow;
    }
  }

  Future<AuthState> login({
    required String email,
    required String password,
  }) async {
    final res = await _client.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    return _persist(res.data);
  }

  /// Exchanges the stored refresh token for a new session (`POST
  /// /auth/refresh`). Returns null when the token is missing, rejected or
  /// the network is unreachable — callers then fall back to a clean
  /// sign-out or the cached identity.
  Future<AuthState?> _tryRefreshSession() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      final res = await _client.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      return _persist(res.data);
    } on ApiException {
      return null;
    }
  }

  Future<AuthState> register({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    final res = await _client.post('/auth/register', data: {
      'email': email,
      'password': password,
      if (firstName != null && firstName.isNotEmpty) 'firstName': firstName,
      if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
      // The backend allow-lists self-registration to `traveler`/`host`
      // server-side; the mobile app creates traveler accounts only.
      'role': 'traveler',
    });
    return _persist(res.data);
  }

  AuthState _persist(Object? data) {
    final map = (data as Map).cast<String, dynamic>();
    final accessToken = map['access_token'] as String? ?? '';
    final refreshToken = map['refresh_token'] as String? ?? '';
    final userJson = jsonEncode(map['user']);
    _client.authInterceptor.setToken(accessToken);
    // ignore: discarded_futures — storage failures are non-fatal to login
    _storage.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userJson: userJson,
    );
    return AuthState(
      status: AuthStatus.authenticated,
      user: AppUser.fromJson((map['user'] as Map).cast<String, dynamic>()),
    );
  }

  Future<void> logout() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        // Revoke the refresh token server-side so a copy of it cannot mint
        // new sessions. Best effort: signing out must work offline.
        await _client.post(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
        );
      } on ApiException {
        // Offline, or the token was already invalid — clear locally anyway.
      }
    }
    await _storage.clear();
    _client.authInterceptor.setToken(null);
  }

  /// Ends every session for the account — all devices and every refresh
  /// token — then clears this device locally.
  Future<void> logoutEverywhere() async {
    try {
      await _client.post('/auth/logout-all');
    } on ApiException {
      // Offline or the session was already invalid: still end it locally.
    }
    await _storage.clear();
    _client.authInterceptor.setToken(null);
  }

  Future<AppUser> fetchProfile() async {
    final res = await _client.get('/profile/me');
    return AppUser.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? bio,
    String? avatarUrl,
  }) async {
    await _client.patch('/profile/me', data: {
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (phone != null) 'phone': phone,
      if (bio != null) 'bio': bio,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    });
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post('/auth/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStorageProvider)),
);

/// Global session state. `AuthStatus.restoring` on first frame while the
/// stored session is validated.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final repo = ref.read(authRepositoryProvider);
    // End the session everywhere when any request returns 401.
    ref.read(apiClientProvider).authInterceptor.onUnauthorized = () {
      repo.logout();
      state = const AuthState(status: AuthStatus.signedOut);
    };
    Future.microtask(() async {
      try {
        state = await repo.restoreSession();
      } on ApiException {
        state = const AuthState(status: AuthStatus.signedOut);
      }
    });
    return const AuthState(status: AuthStatus.restoring);
  }

  Future<void> signIn({required String email, required String password}) async {
    state = await ref
        .read(authRepositoryProvider)
        .login(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    state = await ref.read(authRepositoryProvider).register(
          email: email,
          password: password,
          firstName: firstName,
          lastName: lastName,
        );
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState(status: AuthStatus.signedOut);
  }

  /// Ends the session on every device and signs out here.
  Future<void> signOutEverywhere() async {
    await ref.read(authRepositoryProvider).logoutEverywhere();
    state = const AuthState(status: AuthStatus.signedOut);
  }

  /// Refresh the in-memory user after a profile edit.
  Future<void> refreshProfile() async {
    final user = await ref.read(authRepositoryProvider).fetchProfile();
    state = state.copyWith(status: AuthStatus.authenticated, user: user);
  }

  /// Apply a local-only update (optimistic UI after PATCH).
  void applyLocalUser(AppUser user) {
    state = state.copyWith(status: AuthStatus.authenticated, user: user);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
