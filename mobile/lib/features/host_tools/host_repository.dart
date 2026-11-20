import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/auth_repository.dart';
import 'host_models.dart';

/// Every host-role endpoint this app uses (`/api/v1/host/*`).
///
/// The server's `current_host` dependency rejects any token whose account is
/// not role `host` with 403, so the UI guard below is convenience, never the
/// authorization itself.
///
/// Not surfaced here, deliberately:
/// * `POST /host/bookings` (a host entering an off-platform booking by hand)
/// * marking a booking `completed` — `PATCH /host/bookings/{id}` accepts only
///   `accepted` or `rejected`, so the app does not offer a state the server
///   would refuse.
class HostRepository {
  HostRepository(this._client);

  final ApiClient _client;

  Future<List<HostExperience>> fetchExperiences() async {
    final res = await _client.get('/host/experiences');
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(HostExperience.fromJson)
        .toList(growable: false);
  }

  Future<HostExperience> createExperience(HostExperienceDraft draft) async {
    final res = await _client.post('/host/experiences', data: draft.toJson());
    return HostExperience.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// Full-body update: the endpoint takes `HostExperienceCreate`, not a
  /// partial patch.
  Future<HostExperience> updateExperience(
    int id,
    HostExperienceDraft draft,
  ) async {
    final res =
        await _client.patch('/host/experiences/$id', data: draft.toJson());
    return HostExperience.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteExperience(int id) async {
    await _client.delete('/host/experiences/$id');
  }

  Future<List<HostTour>> fetchTours() async {
    final res = await _client.get('/host/tours');
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(HostTour.fromJson)
        .toList(growable: false);
  }

  Future<HostTour> createTour(HostTourDraft draft) async {
    final res = await _client.post('/host/tours', data: draft.toJson());
    return HostTour.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<HostTour> updateTour(int id, HostTourDraft draft) async {
    final res = await _client.patch('/host/tours/$id', data: draft.toJson());
    return HostTour.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteTour(int id) async {
    await _client.delete('/host/tours/$id');
  }

  Future<List<HostBooking>> fetchBookings() async {
    final res = await _client.get('/host/bookings');
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(HostBooking.fromJson)
        .toList(growable: false);
  }

  /// `accepted` | `rejected` only — the server answers 422 for anything else.
  Future<void> decideBooking(int id, {required bool accept}) async {
    await _client.patch(
      '/host/bookings/$id',
      data: {'status': accept ? 'accepted' : 'rejected'},
    );
  }
}

final hostRepositoryProvider = Provider<HostRepository>(
  (ref) => HostRepository(ref.watch(apiClientProvider)),
);

final hostExperiencesProvider =
    FutureProvider.autoDispose<List<HostExperience>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isHost) throw StateError('Host workspace requires a host session');
  return ref.watch(hostRepositoryProvider).fetchExperiences();
});

final hostToursProvider =
    FutureProvider.autoDispose<List<HostTour>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isHost) throw StateError('Host workspace requires a host session');
  return ref.watch(hostRepositoryProvider).fetchTours();
});

final hostBookingsProvider =
    FutureProvider.autoDispose<List<HostBooking>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isHost) throw StateError('Host workspace requires a host session');
  return ref.watch(hostRepositoryProvider).fetchBookings();
});
