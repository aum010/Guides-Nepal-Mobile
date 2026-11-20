import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../shared/models/review.dart';
import '../auth/auth_repository.dart';

/// Server-persisted favorites via `/profile/bookmarks`.
///
/// Bookmarks store the catalogue row's id (`experience_id`) so a save resolves
/// without parsing `link`. The slug is still written to `link`, keeping rows
/// compatible with older bookmarks and the web app.
class FavoritesRepository {
  FavoritesRepository(this._client);

  final ApiClient _client;

  Future<List<Bookmark>> fetchBookmarks() async {
    final res = await _client.get('/profile/bookmarks');
    return (res.data as List)
        .whereType<Map<String, dynamic>>()
        .map(Bookmark.fromJson)
        .toList(growable: false);
  }

  Future<Bookmark> addBookmark({
    required String title,
    required String slug,
    int? experienceId,
    String? city,
    String? image,
  }) async {
    final res = await _client.post('/profile/bookmarks', data: {
      'title': title,
      'link': slug,
      if (experienceId != null) 'experience_id': experienceId,
      if (city != null) 'city': city,
      if (image != null) 'image': image,
    });
    return Bookmark.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<void> removeBookmark(int id) async {
    await _client.delete('/profile/bookmarks/$id');
  }
}

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => FavoritesRepository(ref.watch(apiClientProvider)),
);

/// Bookmarks for the signed-in user; throws when signed out so screens can
/// prompt for sign-in instead of implying local-only persistence.
final bookmarksProvider = FutureProvider.autoDispose<List<Bookmark>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isAuthenticated) {
    return const <Bookmark>[];
  }
  return ref.watch(favoritesRepositoryProvider).fetchBookmarks();
});
