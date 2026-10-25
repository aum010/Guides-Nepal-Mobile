import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../shared/models/booking.dart';
import '../auth/auth_repository.dart';

/// Payload for `POST /bookings` (matches `BookingCreate` exactly).
class BookingRequest {
  const BookingRequest({
    required this.experienceId,
    required this.experienceTitle,
    required this.city,
    required this.date,
    required this.guests,
    required this.price,
    this.image,
  });

  final int experienceId;
  final String experienceTitle;
  final String city;
  final DateTime date;
  final int guests;

  /// Total price for the booking (price × guests), as accepted by the
  /// backend which stores it verbatim.
  final double price;
  final String? image;

  Map<String, dynamic> toJson() => {
        'experience_id': experienceId,
        'experience_title': experienceTitle,
        'city': city,
        'date': date.toUtc().toIso8601String(),
        'guests': guests,
        'price': price,
        if (image != null) 'image': image,
      };
}

class DayAvailability {
  const DayAvailability({required this.available, required this.status});

  final bool available;
  final String status; // free | booked | reserved

  factory DayAvailability.fromJson(Map<String, dynamic> json) =>
      DayAvailability(
        available: json['available'] == true,
        status: json['status'] as String? ?? 'free',
      );
}

class BookingRepository {
  BookingRepository(this._client);

  final ApiClient _client;

  Future<List<Booking>> fetchBookings() async {
    final res = await _client.get('/bookings/');
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(Booking.fromJson)
        .toList(growable: false);
  }

  /// Never retried automatically — bookings are non-idempotent; the UI
  /// guards against duplicate submissions instead.
  Future<Booking> createBooking(BookingRequest request) async {
    final res = await _client.post('/bookings/', data: request.toJson());
    return Booking.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<Booking> cancelBooking(int id) async {
    final res = await _client.post('/bookings/$id/cancel');
    return Booking.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<Booking> archiveBooking(int id) async {
    final res = await _client.post('/bookings/$id/archive');
    return Booking.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<DayAvailability> fetchAvailability(DateTime date) async {
    final iso = date.toIso8601String().substring(0, 10);
    final res = await _client.get('/bookings/availability', query: {'date': iso});
    return DayAvailability.fromJson((res.data as Map).cast<String, dynamic>());
  }
}

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(ref.watch(apiClientProvider)),
);

/// The traveler's bookings (auth required).
final bookingsProvider = FutureProvider.autoDispose<List<Booking>>((ref) async {
  return ref.watch(bookingRepositoryProvider).fetchBookings();
});
