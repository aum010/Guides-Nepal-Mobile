import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/review.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_repository.dart';
import '../favorites/favorites_repository.dart';

/// Saved tab: the signed-in traveler's server-persisted bookmarks.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final bookmarks = ref.watch(bookmarksProvider);

    if (!auth.isAuthenticated) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: EmptyStateView(
            icon: Icons.favorite_outline,
            title: AppStrings.sessionExpiredTitle,
            message: AppStrings.sessionExpiredBody,
            actionLabel: AppStrings.signIn,
            onAction: () => context.push('/sign-in'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter, AppSpacing.x4, AppSpacing.gutter, 0),
              child: Text(AppStrings.navSaved, style: AppTypography.h1),
            ),
            const SizedBox(height: AppSpacing.x3),
            Expanded(
              child: bookmarks.when(
                loading: () => const SkeletonList(itemCount: 3),
                error: (e, _) => ErrorStateView(
                  message:
                      e is ApiException ? e.message : AppStrings.offlineBody,
                  onRetry: () => ref.invalidate(bookmarksProvider),
                ),
                data: (list) => list.isEmpty
                    ? EmptyStateView(
                        icon: Icons.favorite_outline,
                        title: 'Nothing saved yet',
                        message: 'Tap the heart on any experience to keep '
                            'it here for later.',
                        actionLabel: AppStrings.exploreExperiences,
                        onAction: () => context.go('/explore'),
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(bookmarksProvider),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.gutter),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.x3),
                          itemBuilder: (_, i) =>
                              _BookmarkTile(bookmark: list[i]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkTile extends ConsumerWidget {
  const _BookmarkTile({required this.bookmark});

  final Bookmark bookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slug = bookmark.link ?? '';
    return Dismissible(
      key: ValueKey('bookmark-${bookmark.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.x5),
        decoration: BoxDecoration(
          color: AppColors.errorSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.error),
      ),
      onDismissed: (_) async {
        try {
          await ref
              .read(favoritesRepositoryProvider)
              .removeBookmark(bookmark.id);
          ref.invalidate(bookmarksProvider);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not remove this saved item.')),
            );
          }
        }
      },
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: slug.isEmpty ? null : () => context.push('/experience/$slug'),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.x3),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: NetworkImageView(
                    url: bookmark.image,
                    width: 64,
                    height: 64,
                    semanticsLabel: bookmark.title,
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bookmark.title,
                          style: AppTypography.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        bookmark.city ?? 'Nepal',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
