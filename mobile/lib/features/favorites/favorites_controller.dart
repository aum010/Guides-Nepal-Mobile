import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/experience.dart';
import '../../shared/models/review.dart' show Bookmark;
import '../auth/auth_repository.dart';
import 'favorites_repository.dart';

/// In-memory mirror of the server bookmark list for O(1) "is saved" checks
/// and instant heart toggles.
class FavoritesState {
  const FavoritesState({this.bookmarks = const [], this.loaded = false});

  final List<Bookmark> bookmarks;
  final bool loaded;

  bool isSaved(String slug) {
    final needle = slug.trim();
    return bookmarks.any((b) => b.link?.trim() == needle);
  }

  int? idFor(String slug) {
    final needle = slug.trim();
    for (final b in bookmarks) {
      if (b.link?.trim() == needle) return b.id;
    }
    return null;
  }

  FavoritesState copyWith({List<Bookmark>? bookmarks, bool? loaded}) =>
      FavoritesState(
        bookmarks: bookmarks ?? this.bookmarks,
        loaded: loaded ?? this.loaded,
      );
}

class FavoritesController extends Notifier<FavoritesState> {
  @override
  FavoritesState build() {
    Future.microtask(refresh);
    return const FavoritesState();
  }

  Future<void> refresh() async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthenticated) {
      state = const FavoritesState(loaded: true);
      return;
    }
    try {
      final bookmarks =
          await ref.read(favoritesRepositoryProvider).fetchBookmarks();
      state = FavoritesState(bookmarks: bookmarks, loaded: true);
    } catch (_) {
      // Keep prior state; screens surface errors via their own providers.
      state = state.copyWith(loaded: true);
    }
  }

  /// Optimistic toggle with server reconciliation. Returns the resulting
  /// saved state so callers (cards) can reflect it immediately.
  Future<bool> toggle(Experience experience) async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthenticated) {
      throw StateError('signin-required');
    }
    final wasSaved = state.isSaved(experience.slug);
    final previous = state;

    // Optimistic update.
    if (wasSaved) {
      final id = state.idFor(experience.slug)!;
      state = state.copyWith(
        bookmarks: [
          for (final b in state.bookmarks)
            if (b.id != id) b,
        ],
      );
    } else {
      state = state.copyWith(
        bookmarks: [
          ...state.bookmarks,
          Bookmark(
            id: -DateTime.now().millisecondsSinceEpoch,
            userId: auth.user?.id ?? 0,
            createdAt: DateTime.now(),
            title: experience.title,
            link: experience.slug,
            city: experience.city,
            image: experience.heroImage.isEmpty ? null : experience.heroImage,
          ),
        ],
      );
    }

    try {
      final repo = ref.read(favoritesRepositoryProvider);
      if (wasSaved) {
        await repo.removeBookmark(previous.idFor(experience.slug)!);
      } else {
        await repo.addBookmark(
          title: experience.title,
          slug: experience.slug,
          city: experience.city,
          image: experience.heroImage.isEmpty ? null : experience.heroImage,
        );
      }
      await refresh();
      return !wasSaved;
    } catch (_) {
      // Revert on failure — never imply a save that didn't persist.
      state = previous;
      rethrow;
    }
  }
}

final favoritesControllerProvider =
    NotifierProvider<FavoritesController, FavoritesState>(
        FavoritesController.new);
