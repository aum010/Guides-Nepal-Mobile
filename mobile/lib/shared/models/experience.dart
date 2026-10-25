import 'guide.dart';

/// Experience (tour) as exposed by `GET /api/v1/experiences`.
///
/// The backend serves seeded content rows plus live host experiences;
/// optional fields (`city`, `category`, `guides`) are present on some rows
/// and are parsed defensively.
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
      };
}
