import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/features/host_tools/host_models.dart';
import 'package:guides_nepal/shared/models/booking.dart';

/// Host records are parsed from `backend/app/schemas/host.py` and posted back
/// in the same snake_case spelling. These tests pin the wire contract (so a
/// renamed field fails here, not silently on a device) and the client-side
/// validation that mirrors `HostExperienceCreate` / `HostTourCreate`.
void main() {
  group('HostExperience', () {
    test('parses the response and treats a blank photo as absent', () {
      final experience = HostExperience.fromJson({
        'id': 12,
        'title': 'Newari food walk',
        'city': 'Lalitpur',
        'category': 'Food Tours',
        'description': 'A slow walk through the old town, tasting as we go.',
        'price': 45.5,
        'duration': '3 hours',
        'slug': 'newari-food-walk',
        'is_active': true,
        'hero_image': '   ',
      });

      expect(experience.id, 12);
      expect(experience.price, 45.5);
      expect(experience.isActive, isTrue);
      expect(experience.heroImage, isNull);
    });

    test('a draft round-trips into the create body', () {
      const draft = HostExperienceDraft(
        title: '  Newari food walk  ',
        city: ' Lalitpur ',
        category: 'Food Tours',
        description: 'A slow walk through the old town, tasting as we go.',
        price: '45.5',
        duration: '3 hours',
        heroImage: '  ',
      );

      final body = draft.toJson();
      expect(body['title'], 'Newari food walk');
      expect(body['city'], 'Lalitpur');
      expect(body['price'], 45.5);
      // A blank photo must be sent as null, not an empty string.
      expect(body['hero_image'], isNull);
      expect(draft.validate(), isEmpty);
    });

    test('validation mirrors the server constraints', () {
      const draft = HostExperienceDraft(
        title: 'ab',
        city: '',
        category: '',
        description: 'too short',
        price: '0',
        duration: '   ',
      );

      final errors = draft.validate();
      expect(errors.keys, containsAll(<String>[
        'title',
        'city',
        'category',
        'description',
        'duration',
        'price',
      ]));
    });

    test('an edit draft pre-fills from the record', () {
      const experience = HostExperience(
        id: 3,
        title: 'Bhaktapur pottery',
        city: 'Bhaktapur',
        category: 'Workshop',
        description: 'Throw a pot with a fifth-generation potter.',
        price: 30,
        duration: '2 hours',
        slug: 'bhaktapur-pottery',
        isActive: false,
        heroImage: '/uploads/listings/3/photo.png',
      );

      final draft = HostExperienceDraft.fromExperience(experience);
      expect(draft.price, '30');
      expect(draft.heroImage, '/uploads/listings/3/photo.png');
      expect(draft.validate(), isEmpty);
    });
  });

  group('HostTour', () {
    test('parses the response', () {
      final tour = HostTour.fromJson({
        'id': 5,
        'title': 'Nagarkot sunrise trek',
        'city': 'Bhaktapur',
        'description': 'An early start for the ridge-line sunrise.',
        'itinerary': 'Pickup, climb, sunrise, breakfast.',
        'meeting_point': 'Bhaktapur Durbar Square gate',
        'duration': '6 hours',
        'difficulty': 'Moderate',
        'max_guests': 8,
        'price': 70,
        'is_active': true,
      });

      expect(tour.maxGuests, 8);
      expect(tour.meetingPoint, 'Bhaktapur Durbar Square gate');
      expect(tour.difficulty, 'Moderate');
    });

    test('group size is bounded to the server range', () {
      const base = HostTourDraft(
        title: 'Nagarkot sunrise trek',
        city: 'Bhaktapur',
        description: 'An early start for the ridge-line sunrise.',
        itinerary: 'Pickup, climb, sunrise, breakfast.',
        meetingPoint: 'Bhaktapur Durbar Square gate',
        duration: '6 hours',
        difficulty: 'Moderate',
        price: '70',
      );

      expect(base.copyWith(maxGuests: '0').validate()['maxGuests'], isNotNull);
      expect(
        base.copyWith(maxGuests: '101').validate()['maxGuests'],
        isNotNull,
      );
      expect(base.copyWith(maxGuests: '8').validate(), isEmpty);
    });

    test('toJson posts snake_case fields', () {
      const draft = HostTourDraft(
        title: 'Nagarkot sunrise trek',
        city: 'Bhaktapur',
        description: 'An early start for the ridge-line sunrise.',
        itinerary: 'Pickup, climb, sunrise, breakfast.',
        meetingPoint: 'Bhaktapur Durbar Square gate',
        duration: '6 hours',
        difficulty: 'Moderate',
        maxGuests: '8',
        price: '70',
      );

      final body = draft.toJson();
      expect(body['meeting_point'], 'Bhaktapur Durbar Square gate');
      expect(body['max_guests'], 8);
      expect(body['price'], 70);
    });
  });

  group('HostBooking', () {
    test('only an open request may be accepted or declined', () {
      HostBooking booking(String status) => HostBooking.fromJson({
            'id': 1,
            'experience_id': 12,
            'experience_title': 'Newari food walk',
            'guest_name': 'Asha Rai',
            'guest_email': 'asha@example.com',
            'date': '2026-11-20T09:00:00Z',
            'guests': 2,
            'total_price': 90,
            'status': status,
          });

      expect(booking('upcoming').canDecide, isTrue);
      for (final status in ['accepted', 'rejected', 'completed', 'cancelled']) {
        expect(booking(status).canDecide, isFalse, reason: status);
      }
    });

    test('parses status, guests and a missing phone', () {
      final booking = HostBooking.fromJson({
        'id': 2,
        'experience_id': 9,
        'experience_title': 'Patan heritage walk',
        'guest_name': 'Maya Gurung',
        'guest_email': 'maya@example.com',
        'guest_phone': '',
        'date': '2026-12-01T07:30:00Z',
        'guests': 3,
        'total_price': 135,
        'notes': 'One vegetarian guest.',
        'status': 'accepted',
      });

      expect(booking.status, BookingStatus.accepted);
      expect(booking.guests, 3);
      expect(booking.totalPrice, 135);
      expect(booking.guestPhone, isNull);
    });
  });
}
