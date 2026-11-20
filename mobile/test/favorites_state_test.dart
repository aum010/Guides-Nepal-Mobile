import 'package:flutter_test/flutter_test.dart';

import 'package:guides_nepal/features/favorites/favorites_controller.dart';
import 'package:guides_nepal/shared/models/review.dart';

Bookmark _bookmark(int id, {String? link}) => Bookmark(
      id: id,
      title: 'Experience $id',
      userId: 1,
      createdAt: DateTime(2026, 1, 1),
      link: link,
    );

/// Covers the O(1) "is saved" mirror, including bookmarks whose `link` is
/// null (the backend stores a free-form tuple — a null link must never
/// crash a heart toggle).
void main() {
  test('isSaved matches on slug regardless of padding', () {
    final state = FavoritesState(
      bookmarks: [_bookmark(1, link: ' newari-food-walk ')],
      loaded: true,
    );
    expect(state.isSaved('newari-food-walk'), isTrue);
    expect(state.isSaved('other-slug'), isFalse);
  });

  test('isSaved is false for bookmarks without a link', () {
    final state = FavoritesState(
      bookmarks: [_bookmark(1), _bookmark(2, link: '')],
      loaded: true,
    );
    expect(state.isSaved('anything'), isFalse);
  });

  test('idFor resolves the bookmark id for removal', () {
    final state = FavoritesState(
      bookmarks: [
        _bookmark(1, link: 'a'),
        _bookmark(42, link: 'b'),
      ],
      loaded: true,
    );
    expect(state.idFor('b'), 42);
    expect(state.idFor('missing'), isNull);
  });

  test('copyWith preserves loaded flag and list', () {
    const state = FavoritesState(loaded: true);
    final copy = state.copyWith(bookmarks: [_bookmark(9, link: 'x')]);
    expect(copy.loaded, isTrue);
    expect(copy.bookmarks.single.id, 9);
  });

  test('matches on experience id, keeping the slug as a fallback', () {
    final state = FavoritesState(
      bookmarks: [
        Bookmark(
          id: 7,
          title: 'Saved',
          userId: 1,
          createdAt: DateTime(2026, 1, 1),
          experienceId: 99,
          link: 'renamed-slug',
        ),
      ],
      loaded: true,
    );

    // The experience keeps its id even if its slug is rewritten.
    expect(state.isSaved('a-different-slug', experienceId: 99), isTrue);
    expect(state.idFor('a-different-slug', experienceId: 99), 7);
    // Rows saved before experience_id existed still match on the slug.
    expect(state.isSaved('renamed-slug'), isTrue);
    expect(state.isSaved('a-different-slug', experienceId: 100), isFalse);
  });
}
