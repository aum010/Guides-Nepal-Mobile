import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_repository.dart';
import 'guide_models.dart';

/// All guide-role endpoints (every route is `require_role("guide")` and
/// scoped server-side to the signed-in guide).
class GuideRepository {
  GuideRepository(this._client);

  final ApiClient _client;

  Future<GuideDashboard> fetchDashboard() async {
    final res = await _client.get('/guide/dashboard');
    return GuideDashboard.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<List<GuideBookingRequest>> fetchBookings() async {
    final res = await _client.get('/guide/bookings');
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(GuideBookingRequest.fromJson)
        .toList(growable: false);
  }

  /// status: accepted | rejected | completed | cancelled (backend-validated).
  Future<void> decideBooking(int id, String status) async {
    await _client.patch('/guide/bookings/$id', data: {'status': status});
  }

  Future<List<GuideListing>> fetchListings() async {
    final res = await _client.get('/guide/listings');
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(GuideListing.fromJson)
        .toList(growable: false);
  }

  Future<void> updateListingCapacity(int id, {required int maxGuests}) async {
    await _client.patch(
      '/guide/listings/$id/capacity',
      data: {'max_guests': maxGuests},
    );
  }

  /// `POST /guide/listings` (201 with the created listing).
  Future<GuideListing> createListing(ListingDraft draft) async {
    final res = await _client.post('/guide/listings', data: draft.toJson());
    return GuideListing.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// `PATCH /guide/listings/{id}` — a guide may only touch its own listing.
  Future<GuideListing> updateListing(int id, ListingDraft draft) async {
    final res =
        await _client.patch('/guide/listings/$id', data: draft.toJson());
    return GuideListing.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// Pausing keeps the listing (and its booked guests) but hides it from
  /// travelers; the server enforces ownership.
  Future<void> setListingActive(int id, {required bool isActive}) async {
    await _client.patch('/guide/listings/$id', data: {'is_active': isActive});
  }

  Future<void> deleteListing(int id) async {
    await _client.delete('/guide/listings/$id');
  }

  /// `POST /guide/listings/{id}/photo` — the photo travellers see.
  ///
  /// Bytes rather than a file path, so the same call works on web. The
  /// content type is part of the contract: the server rejects anything that
  /// is not a JPEG/PNG/WebP and checks the bytes, not the name.
  Future<GuideListing> uploadListingPhoto(
    int id, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    final res = await _client.post('/guide/listings/$id/photo', data: form);
    return GuideListing.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// Clears the photo (`PATCH` with an explicit null).
  Future<GuideListing> removeListingPhoto(int id) async {
    final res = await _client.patch(
      '/guide/listings/$id',
      data: {'hero_image': null},
    );
    return GuideListing.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// `GET /guide/onboarding` wraps the profile in `{onboarding, completed}`.
  /// A guide who never onboarded gets `onboarding: null` — an empty draft,
  /// not an error.
  Future<GuideOnboarding> fetchOnboarding() async {
    final res = await _client.get('/guide/onboarding');
    final envelope = (res.data as Map).cast<String, dynamic>();
    final profile = envelope['onboarding'];
    if (profile is! Map) return const GuideOnboarding();
    return GuideOnboarding.fromJson(profile.cast<String, dynamic>());
  }

  Future<void> saveOnboarding(GuideOnboarding profile) async {
    await _client.put('/guide/onboarding', data: profile.toJson());
  }

  Future<List<GuideStatusUpdate>> fetchStatusUpdates({int limit = 20}) async {
    final res = await _client.get('/guide/status', query: {'limit': limit});
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(GuideStatusUpdate.fromJson)
        .toList(growable: false);
  }

  /// `POST /guide/status` — the server rejects a `listing_id` the guide does
  /// not own, so a bad link fails loudly instead of silently detaching.
  Future<GuideStatusUpdate> postStatusUpdate(GuideStatusDraft draft) async {
    final res = await _client.post('/guide/status', data: draft.toJson());
    return GuideStatusUpdate.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteStatusUpdate(int id) async {
    await _client.delete('/guide/status/$id');
  }
}

final guideRepositoryProvider = Provider<GuideRepository>(
  (ref) => GuideRepository(ref.watch(apiClientProvider)),
);

final guideDashboardProvider =
    FutureProvider.autoDispose<GuideDashboard>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isGuide) {
    throw StateError('Guide dashboard requires a guide session');
  }
  return ref.watch(guideRepositoryProvider).fetchDashboard();
});

/// The signed-in guide's profile. A guide who never onboarded gets an empty
/// draft (the server sends `onboarding: null`), never an error.
/// The guide's posted updates, newest first.
final guideStatusProvider =
    FutureProvider.autoDispose<List<GuideStatusUpdate>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isGuide) {
    throw StateError('Guide updates require a guide session');
  }
  return ref.watch(guideRepositoryProvider).fetchStatusUpdates();
});

/// The guide's own listings, used where a list is needed without the
/// Listings tab's manual refresh cycle (status composer, update cards).
final guideListingsProvider =
    FutureProvider.autoDispose<List<GuideListing>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isGuide) {
    throw StateError('Guide listings require a guide session');
  }
  return ref.watch(guideRepositoryProvider).fetchListings();
});

final guideOnboardingProvider =
    FutureProvider.autoDispose<GuideOnboarding>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isGuide) {
    throw StateError('Guide profile requires a guide session');
  }
  return ref.watch(guideRepositoryProvider).fetchOnboarding();
});

final guideBookingsProvider =
    FutureProvider.autoDispose<List<GuideBookingRequest>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isGuide) {
    throw StateError('Guide bookings require a guide session');
  }
  return ref.watch(guideRepositoryProvider).fetchBookings();
});
