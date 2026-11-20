import 'guide.dart';

/// Experience (tour) as exposed by `GET /api/v1/experiences`.
///
/// Three kinds of row share this shape: seeded catalogue content, host-owned
/// experiences, and **published guide listings** (`listing-<slug>`). The last
/// group is the only one with real capacity and trip detail, so those fields
/// are nullable and parsed defensively.
class Experience {
  const Experience({
    required this.id,
    required this.slug,
    required this.title,
    required this.heroImage,
    required this.description,
    required this.host,
    this.price,
    this.duration,
    this.rating,
    this.reviewCount,
    this.city,
    this.category,
    this.guides = const [],
    this.listingId,
    this.area,
    this.difficulty,
    this.meetingPoint,
    this.itinerary,
    this.maxGuests,
    this.availableSpots,
  });

  final int id;
  final String slug;
  final String title;
  final String heroImage;
  final String description;
  final Guide host;
  final num? price;
  final String? duration;
  final double? rating;
  final int? reviewCount;
  final String? city;
  final String? category;
  final List<Guide> guides;

  /// The guide's own listing behind this row, present only on published
  /// listings. Booking such a row goes to that listing's guide.
  final int? listingId;
  final String? area;
  final String? difficulty;
  final String? meetingPoint;
  final String? itinerary;
  final int? maxGuests;

  /// Seats still free on a listing. `null` for seeded/host rows, which track
  /// no capacity at all.
  final int? availableSpots;

  bool get isGuideListing => listingId != null;

  bool get isSoldOut => availableSpots != null && availableSpots! <= 0;

  factory Experience.fromJson(Map<String, dynamic> json) {
    final hostJson = json['host'];
    return Experience(
      id: (json['id'] as num?)?.toInt() ?? 0,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      heroImage: (json['heroImage'] as String?) ?? '',
      description: json['description'] as String? ?? '',
      host: hostJson is Map<String, dynamic>
          ? Guide.fromJson(hostJson)
          : const Guide(
              id: 0,
              name: '',
              image: '',
              role: '',
              rating: 0,
              reviews: 0,
              bio: '',
              languages: [],
              verified: false,
              cities: [],
            ),
      price: json['price'] as num?,
      duration: json['duration'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: (json['reviews'] as num?)?.toInt(),
      city: json['city'] as String?,
      category: json['category'] as String?,
      guides: json['guides'] is List
          ? (json['guides'] as List)
              .whereType<Map<String, dynamic>>()
              .map(Guide.fromJson)
              .toList(growable: false)
          : const [],
      listingId: (json['listingId'] as num?)?.toInt(),
      area: json['area'] as String?,
      difficulty: json['difficulty'] as String?,
      meetingPoint: json['meetingPoint'] as String?,
      itinerary: json['itinerary'] as String?,
      maxGuests: (json['maxGuests'] as num?)?.toInt(),
      availableSpots: (json['availableSpots'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'title': title,
        'heroImage': heroImage,
        'description': description,
        'host': host.toJson(),
        'price': price,
        'duration': duration,
        'rating': rating,
        'reviews': reviewCount,
        'city': city,
        'category': category,
        'guides': guides.map((g) => g.toJson()).toList(),
        'listingId': listingId,
        'area': area,
        'difficulty': difficulty,
        'meetingPoint': meetingPoint,
        'itinerary': itinerary,
        'maxGuests': maxGuests,
        'availableSpots': availableSpots,
      };
}
