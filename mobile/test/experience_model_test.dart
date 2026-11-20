import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/shared/models/experience.dart';

/// A published guide listing is the only catalogue row that carries capacity
/// and trip detail, so the parser has to keep those fields (and stay honest
/// with `null` for seeded rows that do not track them).
void main() {
  Map<String, dynamic> listingJson({Object? availableSpots}) => {
        'id': 200004,
        'slug': 'listing-sarangkot-sunrise',
        'title': 'Sunrise hike to Sarangkot',
        'heroImage': 'https://images.example.com/sarangkot.jpg',
        'description': 'An easy pre-dawn walk above the lake.',
        'price': 45.0,
        'duration': '4 hours',
        'rating': null,
        'reviews': 0,
        'city': 'Pokhara',
        'category': 'Adventure',
        'host': {
          'id': 300002,
          'name': 'Pemba Gurung',
          'image': '',
          'role': 'Local guide',
          'rating': 0.0,
          'reviews': 0,
          'bio': '',
          'languages': ['Nepali'],
          'verified': false,
          'cities': ['Pokhara'],
        },
        'listingId': 4,
        'area': 'Sarangkot ridge',
        'difficulty': 'Moderate',
        'meetingPoint': 'Lakeside taxi stand',
        'itinerary': 'Pickup 4:30 am, ridge by sunrise.',
        'maxGuests': 6,
        'availableSpots': availableSpots,
      };

  test('parses the listing fields and the guide host', () {
    final experience = Experience.fromJson(listingJson(availableSpots: 4));

    expect(experience.isGuideListing, isTrue);
    expect(experience.listingId, 4);
    expect(experience.difficulty, 'Moderate');
    expect(experience.meetingPoint, 'Lakeside taxi stand');
    expect(experience.itinerary, 'Pickup 4:30 am, ridge by sunrise.');
    expect(experience.maxGuests, 6);
    expect(experience.availableSpots, 4);
    expect(experience.isSoldOut, isFalse);
    // The guide account is the host, addressable by its namespaced id.
    expect(experience.host.id, 300002);
    expect(experience.host.name, 'Pemba Gurung');
  });

  test('a listing with no seats left reports itself sold out', () {
    expect(Experience.fromJson(listingJson(availableSpots: 0)).isSoldOut, isTrue);
  });

  test('seeded rows keep capacity unknown rather than zero', () {
    final seeded = Experience.fromJson({
      ...listingJson(availableSpots: null),
      'listingId': null,
      'maxGuests': null,
      'availableSpots': null,
    });

    expect(seeded.isGuideListing, isFalse);
    expect(seeded.availableSpots, isNull);
    // Unknown capacity must never read as "sold out".
    expect(seeded.isSoldOut, isFalse);
  });
}
