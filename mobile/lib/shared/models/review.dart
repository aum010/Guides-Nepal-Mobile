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
/// The backend stores a free-form title/city/image/link tuple rather than
/// an experience id, so the client matches on [link] (which we always set
/// to the experience slug) for de-duplication. This is documented as a
/// contract limitation in `docs/api-gaps.md`.
class Bookmark {
  const Bookmark({
    required this.id,
    required this.title,
    required this.userId,
    required this.createdAt,
    this.city,
    this.image,
    this.link,
  });

  final int id;
  final String title;
  final int userId;
  final DateTime createdAt;
  final String? city;
  final String? image;
  final String? link;

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
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
      };
}
