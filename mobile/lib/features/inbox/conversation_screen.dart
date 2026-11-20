import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// One message thread: history, a send box, and a light poll so the
/// other side's replies appear without a manual refresh.
///
/// Opening the thread is also what marks it read — the list endpoint's
/// `GET …/messages` sets `read_at` server-side — so the Inbox pill
/// clears as soon as the traveler is looking at the conversation.
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    this.pollInterval = const Duration(seconds: 10),
  });

  final int conversationId;

  /// Refresh cadence while the thread is on screen; `null` disables it
  /// (widget tests that drive time manually).
  final Duration? pollInterval;

  @override
  ConsumerState<ConversationScreen> createState() =>
      _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final TextEditingController _composer = TextEditingController();
  Timer? _poll;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final interval = widget.pollInterval;
    if (interval != null) {
      _poll = Timer.periodic(interval, (_) {
        if (mounted) ref.invalidate(messagesProvider(widget.conversationId));
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(inboxRepositoryProvider)
          .send(widget.conversationId, body);
      _composer.clear();
      ref.invalidate(messagesProvider(widget.conversationId));
      ref.invalidate(conversationsProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final conversations = ref.watch(conversationsProvider);
    final messages = ref.watch(messagesProvider(widget.conversationId));

    // The peer comes from the list (one more reason Trips invalidates it
    // after opening a thread); fall back to a neutral title for a deep
    // link whose list entry has not arrived yet.
    final peerName = conversations.maybeWhen(
      data: (list) => list
          .where((c) => c.id == widget.conversationId)
          .map((c) => c.peer.displayName)
          .firstOrNull,
      orElse: () => null,
    );

    final myId = auth.user?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          peerName ?? AppStrings.navInbox,
          style: AppTypography.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const SkeletonList(itemCount: 4),
              error: (e, _) => ErrorStateView(
                message: e is ApiException ? e.message : AppStrings.offlineBody,
                onRetry: () =>
                    ref.invalidate(messagesProvider(widget.conversationId)),
              ),
              data: (list) => list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.x8),
                        child: Text(
                          AppStrings.threadEmptyTitle,
                          style: AppTypography.body
                              .copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(messagesProvider(widget.conversationId)),
                      child: ListView(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.gutter,
                            AppSpacing.x4,
                            AppSpacing.gutter,
                            AppSpacing.x4),
                        children: [
                          for (final message in list.reversed)
                            _MessageBubble(
                              message: message,
                              mine: message.senderId == myId,
                            ),
                        ],
                      ),
                    ),
            ),
          ),
          _ComposerBar(
            controller: _composer,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

/// Chat bubble: mine sits right in primary navy, theirs left on surface
/// white. The timestamp rides under the body inside the bubble.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    const radius = AppSpacing.radiusLg;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x1 + 1),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x3, vertical: AppSpacing.x2),
              constraints: const BoxConstraints(maxWidth: 288),
              decoration: BoxDecoration(
                color: mine ? AppColors.primary : AppColors.surface,
                border: mine ? null : Border.all(color: AppColors.border),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(radius),
                  topRight: const Radius.circular(radius),
                  bottomLeft: Radius.circular(mine ? radius : 4),
                  bottomRight: Radius.circular(mine ? 4 : radius),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.body,
                    style: AppTypography.body.copyWith(
                      color: mine
                          ? AppColors.textOnPrimary
                          : AppColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Formatters.time(message.createdAt),
                    style: AppTypography.caption.copyWith(
                      color: mine
                          ? AppColors.onImageTextSecondary
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed input row pinned above the safe-area inset.
class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter, AppSpacing.x2, AppSpacing.gutter, AppSpacing.x2),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: AppStrings.messageHint,
                  hintStyle: AppTypography.body
                      .copyWith(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x4,
                      vertical: AppSpacing.x2 + 2),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusPill),
                    borderSide: const BorderSide(color: AppColors.secondary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Material(
              color: AppColors.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: SizedBox(
                  width: AppSpacing.minTouchTarget,
                  height: AppSpacing.minTouchTarget,
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.textOnAccent,
                          ),
                        )
                      : const Icon(Icons.send_rounded,
                          size: 21, color: AppColors.textOnAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
