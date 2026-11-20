import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/conversation.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import 'inbox_repository.dart';

/// Inbox tab: real conversations with guides, plus the Maila Dai card
/// for the assistant channel that works at any hour.
///
/// Freshness model (see `docs/api-gaps.md` §2): pull-to-refresh on
/// demand, plus a light [Timer.periodic] poll while the tab is mounted
/// so unread counts catch up without the traveler doing anything. The
/// poll only invalidates a provider — between ticks it schedules no
/// frames, and it is cancelled in `dispose`, so it stays invisible to
/// `pumpAndSettle` and leaves no pending timer behind in tests.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({
    super.key,
    this.pollInterval = const Duration(seconds: 15),
  });

  /// How often the conversation list refreshes while mounted; `null`
  /// disables polling (widget tests that drive time manually).
  final Duration? pollInterval;

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final interval = widget.pollInterval;
    if (interval != null) {
      _poll = Timer.periodic(interval, (_) {
        if (mounted) ref.invalidate(conversationsProvider);
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: !auth.isAuthenticated
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ScreenHeader(
                    title: AppStrings.navInbox,
                    subtitle: AppStrings.inboxSubline,
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  Expanded(
                    child: EmptyStateView(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: AppStrings.sessionExpiredTitle,
                      message: AppStrings.sessionExpiredBody,
                      actionLabel: AppStrings.signIn,
                      onAction: () => context.push('/sign-in'),
                    ),
                  ),
                ],
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(conversationsProvider),
                child: ListView(
                  // Short lists must still overscroll so pull-to-refresh
                  // works before the traveler has many threads.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.only(bottom: AppSpacing.x8),
                  children: [
                    const ScreenHeader(
                      title: AppStrings.navInbox,
                      subtitle: AppStrings.inboxSubline,
                    ),
                    const SizedBox(height: AppSpacing.x6),
                    const _MailaDaiCard(),
                    const SizedBox(height: AppSpacing.x4),
                    conversations.when(
                      loading: () => const SkeletonList(itemCount: 2),
                      error: (e, _) => ErrorStateView(
                        message: e is ApiException
                            ? e.message
                            : AppStrings.offlineBody,
                        onRetry: () =>
                            ref.invalidate(conversationsProvider),
                      ),
                      data: (list) => list.isEmpty
                          ? EmptyStateView(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: AppStrings.inboxEmptyTitle,
                              message: AppStrings.inboxEmptyBody,
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SectionHeader(
                                    title: AppStrings.messagesSection),
                                const SizedBox(height: AppSpacing.x2),
                                for (var i = 0; i < list.length; i++) ...[
                                  _ConversationTile(
                                      conversation: list[i]),
                                  if (i != list.length - 1)
                                    const SizedBox(height: AppSpacing.x3),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// One conversation row: peer identity, preview, age and unread pill.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final peer = conversation.peer;
    final last = conversation.lastMessage;
    final unread = conversation.unreadCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          onTap: () => context.push('/inbox/${conversation.id}'),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.x4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Initials avatar — no fabricated photos for peers that
                // may not have uploaded one.
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfacePeach,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    peer.initials,
                    style: AppTypography.label.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              peer.displayName,
                              style: AppTypography.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unread > 0) ...[
                            const SizedBox(width: AppSpacing.x2),
                            _UnreadPill(count: unread),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        last?.body ?? AppStrings.conversationNoMessages,
                        style: last == null || unread > 0
                            ? AppTypography.caption.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: unread > 0
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              )
                            : AppTypography.caption
                                .copyWith(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        Formatters.relativeTime(
                          last?.createdAt ?? conversation.createdAt,
                        ),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand-yellow unread counter — the one accent that reads as "new"
/// across the app.
class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2 + 2, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      constraints: const BoxConstraints(minWidth: 22),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: AppTypography.badge.copyWith(
          color: AppColors.textOnAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The one channel that works today, promoted rather than buried in an
/// empty state.
class _MailaDaiCard extends StatelessWidget {
  const _MailaDaiCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.secondary, AppColors.primary],
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.onImageFill,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      size: 22, color: AppColors.textOnPrimary),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.mailaDai,
                        style: AppTypography.title
                            .copyWith(color: AppColors.textOnPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your local travel assistant',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textOnPrimary
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x3),
            Text(
              AppStrings.planWithMailaDaiBody,
              style: AppTypography.small.copyWith(
                color: AppColors.textOnPrimary.withValues(alpha: 0.88),
              ),
            ),
            const SizedBox(height: AppSpacing.x4),
            AppButton(
              label: 'Chat with Maila Dai',
              expanded: false,
              onPressed: () => context.push('/ai'),
            ),
          ],
        ),
      ),
    );
  }
}
