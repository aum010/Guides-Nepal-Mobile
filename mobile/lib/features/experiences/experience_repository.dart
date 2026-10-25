import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../shared/models/city_update.dart';
import '../../shared/models/experience.dart';
import '../../shared/models/guide.dart';
import '../../shared/models/review.dart';
import '../auth/auth_repository.dart';

/// Query object for `GET /experiences` (all params verified against
/// `backend/app/api/v1/public.py`).
class ExperienceQuery {
  const ExperienceQuery({
    this.city,
    this.category,
    this.search,
    this.minPrice,
    this.maxPrice,
    this.sort,
  });

  final String? city;
  final String? category;
  final String? search;
  final double? minPrice;
  final double? maxPrice;

  /// One of: price_low | price_high | rating | popular (server-side).
  final String? sort;

  ExperienceQuery copyWith({
    String? Function()? city,
    String? Function()? category,
    String? Function()? search,
    double? Function()? minPrice,
    double? Function()? maxPrice,
    String? Function()? sort,
  }) =>
      ExperienceQuery(
        city: city != null ? city() : this.city,
        category: category != null ? category() : this.category,
        search: search != null ? search() : this.search,
        minPrice: minPrice != null ? minPrice() : this.minPrice,
        maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
        sort: sort != null ? sort() : this.sort,
      );

  bool get isEmpty =>
      city == null &&
      category == null &&
      (search == null || search!.trim().isEmpty) &&
      minPrice == null &&
      maxPrice == null;

  Map<String, dynamic> toParams() => {
        if (city != null && city!.isNotEmpty) 'city': city,
        if (category != null && category!.isNotEmpty) 'category': category,
        if (search != null && search!.trim().isNotEmpty)
          'search': search!.trim(),
        if (minPrice != null) 'min_price': minPrice,
        if (maxPrice != null) 'max_price': maxPrice,
        if (sort != null) 'sort': sort,
      };
}

/// Experiences, guides and reviews — read/write against verified public
/// endpoints.
class ExperienceRepository {
  ExperienceRepository(this._client);

  final ApiClient _client;

  Future<List<Experience>> fetchExperiences(
    ExperienceQuery query, {
    CancelToken? cancelToken,
  }) async {
    final res = await _client.get(
      '/experiences',
      query: query.toParams(),
      cancelToken: cancelToken,
    );
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(Experience.fromJson)
        .toList(growable: false);
  }

  Future<Experience> fetchExperience(String slug) async {
    final res = await _client.get('/experiences/$slug');
    return Experience.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<List<Guide>> fetchGuides({String? city}) async {
    final res = await _client.get(
      '/guides',
      query: {if (city != null) 'city': city},
    );
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(Guide.fromJson)
        .toList(growable: false);
  }

  Future<Guide> fetchGuide(int id) async {
    final res = await _client.get('/guides/$id');
    return Guide.fromJson((res.data as Map).cast<String, dynamic>());
  }

  /// Public review list for an experience (no auth required).
  Future<List<Review>> fetchReviews(int experienceId) async {
    final res = await _client.get('/reviews/', query: {'experience_id': experienceId});
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(Review.fromJson)
        .toList(growable: false);
  }

  /// Traveller-facing guide updates for a city (`GET /updates`).
  ///
  /// Public and city-scoped: the feed carries a guide's display name and
  /// update text only. An empty city returns everything currently live, so
  /// the app always passes one rather than pulling a global feed.
  Future<List<CityUpdate>> fetchCityUpdates(
    String city, {
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    final res = await _client.get(
      '/updates',
      query: {'city': city, 'limit': limit},
      cancelToken: cancelToken,
    );
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(CityUpdate.fromJson)
        .toList(growable: false);
  }

  /// Whether the signed-in traveler may review (requires booking).
  Future<bool> canReview(int experienceId) async {
    final res = await _client
        .get('/reviews/can-review', query: {'experience_id': experienceId});
    return (res.data as Map)['can_review'] == true;
  }

  Future<Review> createReview({
    required int experienceId,
    required int rating,
    String? comment,
  }) async {
    final res = await _client.post('/reviews/', data: {
      'experience_id': experienceId,
      'rating': rating,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    return Review.fromJson((res.data as Map).cast<String, dynamic>());
  }
}

final experienceRepositoryProvider = Provider<ExperienceRepository>(
  (ref) => ExperienceRepository(ref.watch(apiClientProvider)),
);

/// Cached list of all guides (public endpoint, loaded once per session).
final guidesProvider = FutureProvider.autoDispose<List<Guide>>((ref) async {
  return ref.watch(experienceRepositoryProvider).fetchGuides();
});

/// Traveller-facing guide updates for one city. Auto-disposed so switching
/// cities never leaves a stale feed behind.
final cityUpdatesProvider = FutureProvider.autoDispose
    .family<List<CityUpdate>, String>((ref, city) {
  return ref.watch(experienceRepositoryProvider).fetchCityUpdates(city);
});
