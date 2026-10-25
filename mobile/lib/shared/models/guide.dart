/// Local guide as exposed by `GET /api/v1/guides`.
class Guide {
  const Guide({
    required this.id,
    required this.name,
    required this.image,
    required this.role,
    required this.rating,
    required this.reviews,
    required this.bio,
    required this.languages,
    required this.verified,
    required this.cities,
    this.livesIn,
    this.gallery = const [],
    this.isActive = true,
  });

  final int id;
  final String name;
  final String image;
  final String role;
  final double rating;
  final int reviews;
  final String bio;
  final List<String> languages;
  final bool verified;
  final List<String> cities;
  final String? livesIn;
  final List<String> gallery;
  final bool isActive;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  factory Guide.fromJson(Map<String, dynamic> json) => Guide(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        image: json['image'] as String? ?? '',
        role: json['role'] as String? ?? '',
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        reviews: (json['reviews'] as num?)?.toInt() ?? 0,
        bio: json['bio'] as String? ?? '',
        languages: _stringList(json['languages']),
        verified: json['verified'] as bool? ?? false,
        cities: _stringList(json['cities']),
        livesIn: json['livesIn'] as String?,
        gallery: _stringList(json['gallery']),
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'image': image,
        'role': role,
        'rating': rating,
        'reviews': reviews,
        'bio': bio,
        'languages': languages,
        'verified': verified,
        'cities': cities,
        'livesIn': livesIn,
        'gallery': gallery,
        'is_active': isActive,
      };

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const [];
  }
}
