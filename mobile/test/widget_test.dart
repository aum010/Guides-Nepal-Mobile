import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/l10n/app_strings.dart';
import 'package:guides_nepal/core/utils/formatters.dart';
import 'package:guides_nepal/shared/models/booking.dart';
import 'package:guides_nepal/shared/models/experience.dart';

void main() {
  test('app strings expose the core brand copy', () {
    expect(AppStrings.appName, 'Guides Nepal');
    expect(AppStrings.heroHeadline, 'Find your Nepal.');
    expect(AppStrings.tagline, 'Discover Nepal Through Local Eyes');
  });

  test('formatters render booking currency explicitly', () {
    expect(Formatters.price(50), r'$50');
    expect(Formatters.price(49.5), r'$49.50');
    expect(Formatters.pricePerPerson(50), r'$50 / person');
    expect(Formatters.reviewCount(1), '1 review');
    expect(Formatters.reviewCount(12), '12 reviews');
    expect(Formatters.reviewCountShort(45), '45');
    expect(Formatters.reviewCountShort(1234), '1.2k');
    expect(Formatters.reviewCountShort(15000), '15k');
    expect(Formatters.guests(1), '1 guest');
    expect(Formatters.guests(3), '3 guests');
  });

  test('relative times read as ages and fall back to a date', () {
    final now = DateTime.now();
    expect(
      Formatters.relativeTime(now.subtract(const Duration(seconds: 20))),
      'Just now',
    );
    // Clock skew must not produce a negative age.
    expect(
      Formatters.relativeTime(now.add(const Duration(minutes: 5))),
      'Just now',
    );
    expect(
      Formatters.relativeTime(now.subtract(const Duration(minutes: 12))),
      '12 min ago',
    );
    expect(
      Formatters.relativeTime(now.subtract(const Duration(hours: 3))),
      '3 h ago',
    );
    expect(
      Formatters.relativeTime(now.subtract(const Duration(days: 1))),
      'Yesterday',
    );
    expect(
      Formatters.relativeTime(now.subtract(const Duration(days: 4))),
      '4 days ago',
    );
    final old = now.subtract(const Duration(days: 30));
    expect(Formatters.relativeTime(old), Formatters.dateShort(old));
  });

  test('booking status parses server values and flags cancellable ones', () {
    expect(BookingStatus.fromString('upcoming'), BookingStatus.upcoming);
    expect(BookingStatus.fromString('accepted'), BookingStatus.accepted);
    expect(BookingStatus.fromString('completed'), BookingStatus.completed);
    expect(BookingStatus.fromString('cancelled'), BookingStatus.cancelled);
    // Unknown values fall back to the default rather than throwing.
    expect(BookingStatus.fromString('bogus'), BookingStatus.upcoming);
    expect(BookingStatus.fromString(null), BookingStatus.upcoming);

    expect(BookingStatus.upcoming.canCancel, isTrue);
    expect(BookingStatus.accepted.canCancel, isTrue);
    expect(BookingStatus.completed.canCancel, isFalse);
    expect(BookingStatus.cancelled.canCancel, isFalse);
  });

  test('experience parses a populated server row', () {
    final e = Experience.fromJson(const {
      'id': 7,
      'slug': 'newari-food-walk',
      'title': 'Newari Food Walk',
      'heroImage': 'https://cdn.example.com/food.jpg',
      'description': 'Taste your way through Patan.',
      'price': 45,
      'duration': '3 hours',
      'rating': 4.8,
      'reviews': 21,
      'city': 'Lalitpur',
      'category': 'food',
      'host': {
        'id': 1,
        'name': 'Aarati Shrestra',
        'image': '',
        'role': 'Food guide',
        'rating': 4.9,
        'reviews': 130,
        'bio': 'Born in Patan.',
        'languages': ['Nepali', 'English'],
        'verified': true,
        'cities': ['Lalitpur'],
      },
    });

    expect(e.id, 7);
    expect(e.slug, 'newari-food-walk');
    expect(e.title, 'Newari Food Walk');
    expect(e.price, 45);
    expect(e.rating, 4.8);
    expect(e.reviewCount, 21);
    expect(e.city, 'Lalitpur');
    expect(e.category, 'food');
    expect(e.host.name, 'Aarati Shrestra');
    expect(e.host.verified, isTrue);
    expect(e.host.languages, ['Nepali', 'English']);
    expect(e.guides, isEmpty);
  });

  test('experience parses a minimal row without optional fields', () {
    final e = Experience.fromJson(const {
      'id': 1,
      'slug': 'bare',
      'title': 'Bare',
      'heroImage': '',
      'description': '',
      'host': <String, dynamic>{},
    });

    expect(e.price, isNull);
    expect(e.rating, isNull);
    expect(e.reviewCount, isNull);
    expect(e.city, isNull);
    expect(e.category, isNull);
    expect(e.host.name, isEmpty);
    expect(e.host.verified, isFalse);
  });
}
