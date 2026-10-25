import '../../shared/models/booking.dart';

/// A guide-owned listing (`GET /guide/listings`).
class GuideListing {
  const GuideListing({
    required this.id,
    required this.title,
    required this.category,
    required this.city,
    required this.description,
    required this.duration,
    required this.difficulty,
    required this.price,
    required this.maxGuests,
    required this.bookedGuests,
    required this.availableSpots,
    required this.occupancyPct,
    required this.isActive,
    this.area,
    this.itinerary,
    this.meetingPoint,
  });

  final int id;
  final String title;
  final String category; // trekking | tour | specialized
  final String city;
  final String? area;
  final String description;
  final String? itinerary;
  final String? meetingPoint;
  final String duration;
  final String difficulty;
  final double price;
  final int maxGuests;
  final int bookedGuests;
  final int availableSpots;
  final int occupancyPct;
  final bool isActive;

  factory GuideListing.fromJson(Map<String, dynamic> json) => GuideListing(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        category: json['category'] as String? ?? 'tour',
        city: json['city'] as String? ?? '',
        area: json['area'] as String?,
        description: json['description'] as String? ?? '',
        itinerary: json['itinerary'] as String?,
        meetingPoint: json['meeting_point'] as String?,
        duration: json['duration'] as String? ?? '',
        difficulty: json['difficulty'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        maxGuests: (json['max_guests'] as num?)?.toInt() ?? 0,
        bookedGuests: (json['booked_guests'] as num?)?.toInt() ?? 0,
        availableSpots: (json['available_spots'] as num?)?.toInt() ?? 0,
        occupancyPct: (json['occupancy_pct'] as num?)?.toInt() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );
}

/// Editable form state for a listing.
///
/// Validation mirrors the server's `GuideListingCreate` /
/// `GuideListingUpdate` constraints (`backend/app/schemas/guide_dashboard.py`)
/// so a guide sees a problem before a round trip. Price and group size are
/// kept as raw text: that is what a keyboard produces, and parsing happens
/// only after [validate] has accepted the input.
class ListingDraft {
  const ListingDraft({
    this.title = '',
    this.category = 'tour',
    this.city = '',
    this.area = '',
    this.description = '',
    this.itinerary = '',
    this.meetingPoint = '',
    this.duration = '',
    this.difficulty = 'Easy',
    this.priceText = '',
    this.maxGuestsText = '10',
    this.isActive = true,
  });

  /// The backend's `GuideCategory` literal values.
  static const List<String> categories = ['trekking', 'tour', 'specialized'];

  /// Difficulty is free text server-side; these are the labels the app
  /// offers. The chips show them lower-cased.
  static const List<String> difficulties = ['Easy', 'Moderate', 'Challenging'];

  final String title;
  final String category;
  final String city;
  final String area;
  final String description;
  final String itinerary;
  final String meetingPoint;
  final String duration;
  final String difficulty;
  final String priceText;
  final String maxGuestsText;
  final bool isActive;

  factory ListingDraft.fromListing(GuideListing listing) => ListingDraft(
        title: listing.title,
        category: listing.category,
        city: listing.city,
        area: listing.area ?? '',
        description: listing.description,
        itinerary: listing.itinerary ?? '',
        meetingPoint: listing.meetingPoint ?? '',
        duration: listing.duration,
        difficulty: listing.difficulty,
        priceText: _trimDecimal(listing.price),
        maxGuestsText: '${listing.maxGuests}',
        isActive: listing.isActive,
      );

  double? get price => double.tryParse(priceText.trim());
  int? get maxGuests => int.tryParse(maxGuestsText.trim());

  static String _trimDecimal(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';

  /// `field name -> message` for every field that would be rejected by the
  /// API. An empty map means the draft is safe to send.
  Map<String, String> validate() {
    final errors = <String, String>{};

    final t = title.trim();
    if (t.isEmpty) {
      errors['title'] = 'Give your experience a title.';
    } else if (t.length < 3) {
      errors['title'] = 'Use at least 3 characters.';
    } else if (t.length > 160) {
      errors['title'] = 'Keep the title under 160 characters.';
    }

    if (!categories.contains(category)) {
      errors['category'] = 'Pick a category.';
    }

    if (city.trim().length < 2) {
      errors['city'] = 'Which city is this in?';
    } else if (city.trim().length > 80) {
      errors['city'] = 'Keep the city under 80 characters.';
    }

    if (area.trim().length > 160) {
      errors['area'] = 'Keep the area under 160 characters.';
    }

    final d = description.trim();
    if (d.isEmpty) {
      errors['description'] = 'Describe the experience.';
    } else if (d.length < 10) {
      errors['description'] = 'Use at least 10 characters.';
    } else if (d.length > 5000) {
      errors['description'] = 'Keep the description under 5000 characters.';
    }

    if (itinerary.trim().length > 5000) {
      errors['itinerary'] = 'Keep the itinerary under 5000 characters.';
    }

    if (meetingPoint.trim().length > 300) {
      errors['meetingPoint'] = 'Keep the meeting point under 300 characters.';
    }

    final dur = duration.trim();
    if (dur.isEmpty) {
      errors['duration'] = 'How long does it last? e.g. 4 hours.';
    } else if (dur.length > 80) {
      errors['duration'] = 'Keep the duration under 80 characters.';
    }

    final diff = difficulty.trim();
    if (diff.length < 2) {
      errors['difficulty'] = 'Pick a difficulty.';
    } else if (diff.length > 40) {
      errors['difficulty'] = 'Keep the difficulty under 40 characters.';
    }

    final p = price;
    if (p == null) {
      errors['price'] = 'Enter a price, e.g. 50.';
    } else if (p < 0) {
      errors['price'] = 'Price cannot be negative.';
    }

    final g = maxGuests;
    if (g == null) {
      errors['maxGuests'] = 'Enter the maximum group size.';
    } else if (g < 1) {
      errors['maxGuests'] = 'At least one guest.';
    } else if (g > 100) {
      errors['maxGuests'] = 'Up to 100 guests.';
    }

    return errors;
  }

  /// Request body for `POST /guide/listings` and `PATCH /guide/listings/{id}`.
  /// Empty optional text is sent as `null` so clearing a field clears it
  /// server-side.
  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'category': category,
        'city': city.trim(),
        'area': _nullIfEmpty(area),
        'description': description.trim(),
        'itinerary': _nullIfEmpty(itinerary),
        'meeting_point': _nullIfEmpty(meetingPoint),
        'duration': duration.trim(),
        'difficulty': difficulty.trim(),
        'price': price,
        'max_guests': maxGuests,
        'is_active': isActive,
      };

  static String? _nullIfEmpty(String value) {
    final v = value.trim();
    return v.isEmpty ? null : v;
  }
}

/// Aggregated dashboard payload (`GET /guide/dashboard`).
class GuideDashboard {
  const GuideDashboard({required this.stats, required this.listings});

  final GuideStats stats;
  final List<GuideListing> listings;

  factory GuideDashboard.fromJson(Map<String, dynamic> json) => GuideDashboard(
        stats: GuideStats.fromJson(
          (json['stats'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        listings: (json['listings'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(GuideListing.fromJson)
            .toList(growable: false),
      );
}

class GuideStats {
  const GuideStats({
    required this.listings,
    required this.upcomingBookings,
    required this.totalGuests,
    required this.totalCapacity,
    required this.bookedCapacity,
    required this.availableSpots,
  });

  final int listings;
  final int upcomingBookings;
  final int totalGuests;
  final int totalCapacity;
  final int bookedCapacity;
  final int availableSpots;

  factory GuideStats.fromJson(Map<String, dynamic> json) => GuideStats(
        listings: (json['listings'] as num?)?.toInt() ?? 0,
        upcomingBookings: (json['upcoming_bookings'] as num?)?.toInt() ?? 0,
        totalGuests: (json['total_guests'] as num?)?.toInt() ?? 0,
        totalCapacity: (json['total_capacity'] as num?)?.toInt() ?? 0,
        bookedCapacity: (json['booked_capacity'] as num?)?.toInt() ?? 0,
        availableSpots: (json['available_spots'] as num?)?.toInt() ?? 0,
      );
}

/// Booking request row for guides (`GET /guide/bookings`).
class GuideBookingRequest {
  const GuideBookingRequest({
    required this.id,
    required this.experienceTitle,
    required this.city,
    required this.date,
    required this.guests,
    required this.price,
    required this.status,
    required this.travelerName,
    this.image,
    this.travelerEmail,
  });

  final int id;
  final String experienceTitle;
  final String city;
  final DateTime date;
  final int guests;
  final double price;
  final BookingStatus status;
  final String travelerName;
  final String? travelerEmail;
  final String? image;

  factory GuideBookingRequest.fromJson(Map<String, dynamic> json) =>
      GuideBookingRequest(
        id: (json['id'] as num?)?.toInt() ?? 0,
        experienceTitle: json['experience_title'] as String? ?? '',
        city: json['city'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        guests: (json['guests'] as num?)?.toInt() ?? 1,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        status: BookingStatus.fromString(json['status'] as String?),
        travelerName: json['traveler_name'] as String? ?? '',
        travelerEmail: json['traveler_email'] as String?,
        image: json['image'] as String?,
      );
}

/// Onboarding profile (`GET/PUT /guide/onboarding`).
class GuideOnboarding {
  const GuideOnboarding({
    this.displayName,
    this.expertiseAreas = const [],
    this.cities = const [],
    this.languages = const [],
    this.bio,
    this.yearsExperience,
    this.defaultMaxGuests = 10,
    this.onboardingCompleted = false,
  });

  final String? displayName;
  final List<String> expertiseAreas;
  final List<String> cities;
  final List<String> languages;
  final String? bio;
  final String? yearsExperience;
  final int defaultMaxGuests;
  final bool onboardingCompleted;

  factory GuideOnboarding.fromJson(Map<String, dynamic> json) =>
      GuideOnboarding(
        displayName: json['display_name'] as String?,
        expertiseAreas: _strList(json['expertise_areas']),
        cities: _strList(json['cities']),
        languages: _strList(json['languages']),
        bio: json['bio'] as String?,
        yearsExperience: json['years_experience'] as String?,
        defaultMaxGuests: (json['default_max_guests'] as num?)?.toInt() ?? 10,
        onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        'expertise_areas': expertiseAreas,
        'cities': cities,
        'languages': languages,
        'bio': bio,
        'years_experience': yearsExperience,
        'default_max_guests': defaultMaxGuests,
        'onboarding_completed': onboardingCompleted,
      };

  static List<String> _strList(Object? v) =>
      v is List ? v.whereType<String>().toList(growable: false) : const [];
}

/// Editable form state for the guide's own profile (`GET|PUT /guide/onboarding`).
///
/// Field limits mirror `GuideOnboardingCreate`
/// (`backend/app/schemas/guide_dashboard.py`). The completion requirements are
/// client-side only: the server stores whatever it is sent, so a guide can
/// save a half-finished profile as a draft and mark it ready later.
class GuideProfileDraft {
  const GuideProfileDraft({
    this.displayName = '',
    this.expertiseAreas = const [],
    this.cities = const [],
    this.languages = const [],
    this.bio = '',
    this.yearsExperience = '',
    this.defaultMaxGuestsText = '10',
    this.onboardingCompleted = false,
  });

  /// Expertise tags offered as chips. The field is free text server-side, so a
  /// value the app does not offer is kept as an extra chip rather than being
  /// silently dropped.
  static const List<String> expertiseOptions = [
    'trekking',
    'tour',
    'culture',
    'food',
    'photography',
    'wildlife',
    'wellness',
  ];

  /// Languages offered as chips (also free text server-side).
  static const List<String> languageOptions = [
    'Nepali',
    'English',
    'Hindi',
    'Newari',
    'Tibetan',
    'Sherpa',
    'Gurung',
    'Tamang',
  ];

  static const int maxNameLength = 160;
  static const int maxBioLength = 5000;
  static const int maxYearsLength = 40;
  static const int minBioLength = 20;

  final String displayName;
  final List<String> expertiseAreas;
  final List<String> cities;
  final List<String> languages;
  final String bio;
  final String yearsExperience;
  final String defaultMaxGuestsText;
  final bool onboardingCompleted;

  factory GuideProfileDraft.fromProfile(GuideOnboarding profile) =>
      GuideProfileDraft(
        displayName: profile.displayName ?? '',
        expertiseAreas: List<String>.of(profile.expertiseAreas),
        cities: List<String>.of(profile.cities),
        languages: List<String>.of(profile.languages),
        bio: profile.bio ?? '',
        yearsExperience: profile.yearsExperience ?? '',
        defaultMaxGuestsText: '${profile.defaultMaxGuests}',
        onboardingCompleted: profile.onboardingCompleted,
      );

  int? get defaultMaxGuests => int.tryParse(defaultMaxGuestsText.trim());

  /// What still separates this profile from a complete one, as short noun
  /// phrases (`['a display name', 'a city']`). Empty when nothing is missing.
  /// Drives both the workspace prompt and the completion validation.
  List<String> missingForCompletion() => [
        if (displayName.trim().length < 2) 'a display name',
        if (expertiseAreas.isEmpty) 'an expertise area',
        if (cities.isEmpty) 'a city',
        if (languages.isEmpty) 'a language',
        if (bio.trim().length < minBioLength) 'a short bio',
      ];

  /// `field name -> message` for every value the API would reject, plus — only
  /// while [onboardingCompleted] is claimed — the fields a profile cannot be
  /// marked ready without. An empty map means the draft is safe to send.
  Map<String, String> validate() {
    final errors = <String, String>{};

    final name = displayName.trim();
    if (name.length > maxNameLength) {
      errors['displayName'] = 'Keep the name under 160 characters.';
    }

    final b = bio.trim();
    if (b.length > maxBioLength) {
      errors['bio'] = 'Keep the bio under 5000 characters.';
    }

    if (yearsExperience.trim().length > maxYearsLength) {
      errors['yearsExperience'] = 'Keep this under 40 characters.';
    }

    final g = defaultMaxGuests;
    if (g == null) {
      errors['defaultMaxGuests'] = 'Enter a group size, e.g. 10.';
    } else if (g < 1) {
      errors['defaultMaxGuests'] = 'At least one guest.';
    } else if (g > 100) {
      errors['defaultMaxGuests'] = 'Up to 100 guests.';
    }

    // A draft may be saved at any point — these only gate "profile complete".
    if (onboardingCompleted) {
      if (name.length < 2) {
        errors['displayName'] = 'Add the name travelers will see.';
      }
      if (expertiseAreas.isEmpty) {
        errors['expertiseAreas'] = 'Pick at least one expertise area.';
      }
      if (cities.isEmpty) {
        errors['cities'] = 'Pick at least one city.';
      }
      if (languages.isEmpty) {
        errors['languages'] = 'Pick at least one language.';
      }
      if (b.isEmpty) {
        errors['bio'] = 'Tell travelers about yourself.';
      } else if (b.length < minBioLength) {
        errors['bio'] = 'Use at least $minBioLength characters.';
      }
    }

    return errors;
  }

  /// The `GuideOnboardingCreate` body. Empty optional text is sent as `null`
  /// so clearing a field clears it server-side.
  GuideOnboarding toProfile() => GuideOnboarding(
        displayName: _nullIfEmpty(displayName),
        expertiseAreas: expertiseAreas,
        cities: cities,
        languages: languages,
        bio: _nullIfEmpty(bio),
        yearsExperience: _nullIfEmpty(yearsExperience),
        defaultMaxGuests: defaultMaxGuests ?? 10,
        onboardingCompleted: onboardingCompleted,
      );

  static String? _nullIfEmpty(String value) {
    final v = value.trim();
    return v.isEmpty ? null : v;
  }
}

/// One update posted by a guide (`GET /guide/status`).
class GuideStatusUpdate {
  const GuideStatusUpdate({
    required this.id,
    required this.updateType,
    required this.message,
    required this.isActive,
    this.listingId,
    this.area,
    this.eventDate,
    this.currentCapacity,
    this.maxCapacity,
    this.createdAt,
  });

  /// The backend's `GuideUpdateType` literals.
  static const List<String> types = [
    'announcement',
    'availability',
    'capacity',
    'booking',
    'schedule',
  ];

  final int id;
  final String updateType;
  final String message;
  final int? listingId;
  final String? area;
  final DateTime? eventDate;
  final int? currentCapacity;
  final int? maxCapacity;
  final bool isActive;
  final DateTime? createdAt;

  factory GuideStatusUpdate.fromJson(Map<String, dynamic> json) =>
      GuideStatusUpdate(
        id: (json['id'] as num?)?.toInt() ?? 0,
        updateType: json['update_type'] as String? ?? 'announcement',
        message: json['message'] as String? ?? '',
        listingId: (json['listing_id'] as num?)?.toInt(),
        area: json['area'] as String?,
        eventDate: DateTime.tryParse(json['event_date'] as String? ?? ''),
        currentCapacity: (json['current_capacity'] as num?)?.toInt(),
        maxCapacity: (json['max_capacity'] as num?)?.toInt(),
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );

  /// `availability` → `Availability`. An unknown server value is shown as
  /// written instead of being hidden.
  String get typeLabel => updateType.isEmpty
      ? 'Update'
      : '${updateType[0].toUpperCase()}${updateType.substring(1)}';
}

/// Composer state for `POST /guide/status`.
///
/// Mirrors `GuideStatusCreate` (`backend/app/schemas/guide_dashboard.py`).
/// Capacity numbers are only sent for a `capacity` update and the date only
/// for a `schedule` — the two types where they mean something.
class GuideStatusDraft {
  const GuideStatusDraft({
    this.updateType = 'announcement',
    this.message = '',
    this.listingId,
    this.area = '',
    this.eventDate,
    this.currentCapacityText = '',
    this.maxCapacityText = '',
  });

  final String updateType;
  final String message;
  final int? listingId;
  final String area;
  final DateTime? eventDate;
  final String currentCapacityText;
  final String maxCapacityText;

  bool get hasCapacity => updateType == 'capacity';
  bool get hasEventDate => updateType == 'schedule';

  int? get currentCapacity => int.tryParse(currentCapacityText.trim());
  int? get maxCapacity => int.tryParse(maxCapacityText.trim());

  /// `field name -> message` for every value the API would reject. An empty
  /// map means the draft is safe to send.
  Map<String, String> validate() {
    final errors = <String, String>{};

    if (!GuideStatusUpdate.types.contains(updateType)) {
      errors['updateType'] = 'Pick what kind of update this is.';
    }

    final m = message.trim();
    if (m.isEmpty) {
      errors['message'] = 'Write the update.';
    } else if (m.length < 3) {
      errors['message'] = 'Use at least 3 characters.';
    } else if (m.length > 2000) {
      errors['message'] = 'Keep the update under 2000 characters.';
    }

    if (area.trim().length > 160) {
      errors['area'] = 'Keep the area under 160 characters.';
    }

    if (hasEventDate && eventDate == null) {
      errors['eventDate'] = 'Pick the date this applies to.';
    }

    if (hasCapacity) {
      final current = currentCapacity;
      final max = maxCapacity;

      if (currentCapacityText.trim().isEmpty) {
        errors['currentCapacity'] = 'How many spots are already taken?';
      } else if (current == null) {
        errors['currentCapacity'] = 'Enter a whole number.';
      } else if (current < 0) {
        errors['currentCapacity'] = 'Cannot be negative.';
      } else if (current > 1000) {
        errors['currentCapacity'] = 'Up to 1000.';
      }

      if (maxCapacityText.trim().isEmpty) {
        errors['maxCapacity'] = 'What is the total capacity?';
      } else if (max == null) {
        errors['maxCapacity'] = 'Enter a whole number.';
      } else if (max < 1) {
        errors['maxCapacity'] = 'At least one spot.';
      } else if (max > 1000) {
        errors['maxCapacity'] = 'Up to 1000 spots.';
      } else if (current != null && current > max) {
        errors['currentCapacity'] = 'Booked cannot exceed the total capacity.';
      }
    }

    return errors;
  }

  /// Request body for `POST /guide/status`.
  Map<String, dynamic> toJson() => {
        'update_type': updateType,
        'message': message.trim(),
        'listing_id': listingId,
        'area': area.trim().isEmpty ? null : area.trim(),
        if (eventDate != null) 'event_date': eventDate!.toIso8601String(),
        if (hasCapacity) 'current_capacity': currentCapacity,
        if (hasCapacity) 'max_capacity': maxCapacity,
      };
}
