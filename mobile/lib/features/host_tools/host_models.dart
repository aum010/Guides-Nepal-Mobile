import '../../l10n/app_strings.dart';
import '../../shared/models/booking.dart';

/// An optional server string that arrives as `null`, `""` or whitespace is
/// treated as absent so the UI shows a fallback instead of an empty box.
String? _blankToNull(Object? value) {
  if (value is! String) return null;
  return value.trim().isEmpty ? null : value;
}

/// Host-owned records from `backend/app/schemas/host.py`.
///
/// The host role is separate from guide: these endpoints are
/// `GET/POST /host/experiences`, `/host/tours`, `/host/bookings` and they are
/// scoped server-side to the signed-in host (`current_host` rejects anything
/// whose role is not `host`). Nothing here is shared with the guide
/// workspace.

/// `HostExperienceResponse`.
class HostExperience {
  const HostExperience({
    required this.id,
    required this.title,
    required this.city,
    required this.category,
    required this.description,
    required this.price,
    required this.duration,
    required this.slug,
    required this.isActive,
    this.heroImage,
  });

  final int id;
  final String title;
  final String city;
  final String category;
  final String description;
  final double price;
  final String duration;
  final String slug;
  final bool isActive;
  final String? heroImage;

  factory HostExperience.fromJson(Map<String, dynamic> json) => HostExperience(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        city: json['city'] as String? ?? '',
        category: json['category'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        duration: json['duration'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? true,
        heroImage: _blankToNull(json['hero_image']),
      );
}

/// Editable form state for a host experience.
///
/// `PATCH /host/experiences/{id}` takes the **whole** `HostExperienceCreate`
/// body (it assigns every field), so an edit always sends every field rather
/// than a partial patch. Validation mirrors the server's constraints so a host
/// sees a problem before a round trip.
class HostExperienceDraft {
  const HostExperienceDraft({
    this.title = '',
    this.city = '',
    this.category = '',
    this.description = '',
    this.price = '',
    this.duration = '',
    this.heroImage = '',
  });

  final String title;
  final String city;
  final String category;
  final String description;
  final String price;
  final String duration;
  final String heroImage;

  factory HostExperienceDraft.fromExperience(HostExperience e) =>
      HostExperienceDraft(
        title: e.title,
        city: e.city,
        category: e.category,
        description: e.description,
        price: e.price == e.price.roundToDouble()
            ? e.price.toStringAsFixed(0)
            : e.price.toString(),
        duration: e.duration,
        heroImage: e.heroImage ?? '',
      );

  HostExperienceDraft copyWith({
    String? title,
    String? city,
    String? category,
    String? description,
    String? price,
    String? duration,
    String? heroImage,
  }) =>
      HostExperienceDraft(
        title: title ?? this.title,
        city: city ?? this.city,
        category: category ?? this.category,
        description: description ?? this.description,
        price: price ?? this.price,
        duration: duration ?? this.duration,
        heroImage: heroImage ?? this.heroImage,
      );

  /// Field-keyed errors, empty when the draft is postable.
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (title.trim().length < 3) errors['title'] = AppStrings.hostTitleTooShort;
    if (city.trim().length < 2) errors['city'] = AppStrings.hostCityRequired;
    if (category.trim().length < 2) {
      errors['category'] = AppStrings.hostCategoryRequired;
    }
    if (description.trim().length < 30) {
      errors['description'] = AppStrings.hostDescriptionTooShort;
    }
    if (duration.trim().isEmpty) {
      errors['duration'] = AppStrings.hostDurationRequired;
    }
    final amount = double.tryParse(price.trim());
    if (amount == null || amount <= 0) {
      errors['price'] = AppStrings.hostPriceInvalid;
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'city': city.trim(),
        'category': category.trim(),
        'description': description.trim(),
        'price': double.tryParse(price.trim()) ?? 0,
        'duration': duration.trim(),
        'hero_image':
            heroImage.trim().isEmpty ? null : heroImage.trim(),
      };
}

/// `HostTourResponse`.
class HostTour {
  const HostTour({
    required this.id,
    required this.title,
    required this.city,
    required this.description,
    required this.itinerary,
    required this.meetingPoint,
    required this.duration,
    required this.difficulty,
    required this.maxGuests,
    required this.price,
    required this.isActive,
  });

  final int id;
  final String title;
  final String city;
  final String description;
  final String itinerary;
  final String meetingPoint;
  final String duration;
  final String difficulty;
  final int maxGuests;
  final double price;
  final bool isActive;

  factory HostTour.fromJson(Map<String, dynamic> json) => HostTour(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        city: json['city'] as String? ?? '',
        description: json['description'] as String? ?? '',
        itinerary: json['itinerary'] as String? ?? '',
        meetingPoint: json['meeting_point'] as String? ?? '',
        duration: json['duration'] as String? ?? '',
        difficulty: json['difficulty'] as String? ?? '',
        maxGuests: (json['max_guests'] as num?)?.toInt() ?? 1,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );
}

/// Editable form state for a host tour (`HostTourCreate`).
class HostTourDraft {
  const HostTourDraft({
    this.title = '',
    this.city = '',
    this.description = '',
    this.itinerary = '',
    this.meetingPoint = '',
    this.duration = '',
    this.difficulty = '',
    this.maxGuests = '',
    this.price = '',
  });

  final String title;
  final String city;
  final String description;
  final String itinerary;
  final String meetingPoint;
  final String duration;
  final String difficulty;
  final String maxGuests;
  final String price;

  factory HostTourDraft.fromTour(HostTour t) => HostTourDraft(
        title: t.title,
        city: t.city,
        description: t.description,
        itinerary: t.itinerary,
        meetingPoint: t.meetingPoint,
        duration: t.duration,
        difficulty: t.difficulty,
        maxGuests: '${t.maxGuests}',
        price: t.price == t.price.roundToDouble()
            ? t.price.toStringAsFixed(0)
            : t.price.toString(),
      );

  HostTourDraft copyWith({
    String? title,
    String? city,
    String? description,
    String? itinerary,
    String? meetingPoint,
    String? duration,
    String? difficulty,
    String? maxGuests,
    String? price,
  }) =>
      HostTourDraft(
        title: title ?? this.title,
        city: city ?? this.city,
        description: description ?? this.description,
        itinerary: itinerary ?? this.itinerary,
        meetingPoint: meetingPoint ?? this.meetingPoint,
        duration: duration ?? this.duration,
        difficulty: difficulty ?? this.difficulty,
        maxGuests: maxGuests ?? this.maxGuests,
        price: price ?? this.price,
      );

  Map<String, String> validate() {
    final errors = <String, String>{};
    if (title.trim().length < 3) errors['title'] = AppStrings.hostTitleTooShort;
    if (city.trim().length < 2) errors['city'] = AppStrings.hostCityRequired;
    if (description.trim().length < 30) {
      errors['description'] = AppStrings.hostDescriptionTooShort;
    }
    if (itinerary.trim().length < 10) {
      errors['itinerary'] = AppStrings.hostItineraryTooShort;
    }
    if (meetingPoint.trim().length < 2) {
      errors['meetingPoint'] = AppStrings.hostMeetingPointRequired;
    }
    if (duration.trim().isEmpty) {
      errors['duration'] = AppStrings.hostDurationRequired;
    }
    if (difficulty.trim().length < 2) {
      errors['difficulty'] = AppStrings.hostDifficultyRequired;
    }
    final guests = int.tryParse(maxGuests.trim());
    if (guests == null || guests < 1 || guests > 100) {
      errors['maxGuests'] = AppStrings.hostMaxGuestsInvalid;
    }
    final amount = double.tryParse(price.trim());
    if (amount == null || amount <= 0) {
      errors['price'] = AppStrings.hostPriceInvalid;
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'city': city.trim(),
        'description': description.trim(),
        'itinerary': itinerary.trim(),
        'meeting_point': meetingPoint.trim(),
        'duration': duration.trim(),
        'difficulty': difficulty.trim(),
        'max_guests': int.tryParse(maxGuests.trim()) ?? 1,
        'price': double.tryParse(price.trim()) ?? 0,
      };
}

/// `HostBookingResponse` — a booking made against one of the host's
/// experiences. Its status vocabulary is the same as a traveller booking's
/// (`upcoming | accepted | rejected | completed | cancelled`), so the shared
/// [BookingStatus] and status chip are reused rather than re-mapped.
class HostBooking {
  const HostBooking({
    required this.id,
    required this.experienceId,
    required this.experienceTitle,
    required this.guestName,
    required this.guestEmail,
    required this.date,
    required this.guests,
    required this.totalPrice,
    required this.status,
    this.guestPhone,
    this.notes,
  });

  final int id;
  final int experienceId;
  final String experienceTitle;
  final String guestName;
  final String guestEmail;
  final String? guestPhone;
  final DateTime date;
  final int guests;
  final double totalPrice;
  final String? notes;
  final BookingStatus status;

  /// The host can only accept or decline a request that is still open:
  /// `PATCH /host/bookings/{id}` accepts exactly those two decisions.
  bool get canDecide => status == BookingStatus.upcoming;

  factory HostBooking.fromJson(Map<String, dynamic> json) => HostBooking(
        id: (json['id'] as num?)?.toInt() ?? 0,
        experienceId: (json['experience_id'] as num?)?.toInt() ?? 0,
        experienceTitle: json['experience_title'] as String? ?? '',
        guestName: json['guest_name'] as String? ?? '',
        guestEmail: json['guest_email'] as String? ?? '',
        guestPhone: _blankToNull(json['guest_phone']),
        date: DateTime.tryParse(json['date'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        guests: (json['guests'] as num?)?.toInt() ?? 1,
        totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] as String?,
        status: BookingStatus.fromString(json['status'] as String?),
      );
}
