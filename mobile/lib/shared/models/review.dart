/// Review for an experience (`GET/POST /api/v1/reviews`).
class Review {
  const Review({
    required this.id,
    required this.experienceId,
    required this.rating,
    required this.userId,
    required this.createdAt,
    this.comment,
    this.userName,
    this.updatedAt,
  });

  final int id;
  final int experienceId;
  final int rating;
  final int userId;
  final DateTime createdAt;
  final String? comment;
  final String? userName;
  final DateTime? updatedAt;

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: (json['id'] as num?)?.toInt() ?? 0,
        experienceId: (json['experience_id'] as num?)?.toInt() ?? 0,
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        comment: json['comment'] as String?,
        userName: json['user_name'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      );
}

/// Server bookmark (`/profile/bookmarks`).
///
/// Bookmarks now carry an optional `experience_id`, so a save resolves back to
/// the catalogue row directly. Rows created before that field existed (and any
/// written by the web app) only have the free-form tuple, so [link] — which the
/// app always sets to the experience slug — remains as a fallback.
class Bookmark {
  const Bookmark({
    required this.id,
    required this.title,
    required this.userId,
    required this.createdAt,
    this.experienceId,
    this.city,
    this.image,
    this.link,
  });

  final int id;
  final String title;
  final int userId;
  final DateTime createdAt;
  final int? experienceId;
  final String? city;
  final String? image;
  final String? link;

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        experienceId: (json['experience_id'] as num?)?.toInt(),
        city: json['city'] as String?,
        image: json['image'] as String?,
        link: json['link'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'city': city,
        'image': image,
        'link': link,
        if (experienceId != null) 'experience_id': experienceId,
      };
}
