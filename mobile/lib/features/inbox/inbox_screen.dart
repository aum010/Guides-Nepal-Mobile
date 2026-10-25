import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/widgets.dart';

/// Inbox tab.
///
/// Contract note (see `docs/api-gaps.md`): the backend does not expose a
/// traveler-facing messaging/conversation API, so there are no conversation
/// threads to list. Rather than fabricate messages, this screen states that
/// direct messaging is not live yet and gives travelers the channel that
/// *does* work — Maila Dai.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.x8),
          children: const [
            ScreenHeader(
              title: AppStrings.navInbox,
              subtitle: AppStrings.inboxSubline,
            ),
            SizedBox(height: AppSpacing.x6),
            _MailaDaiCard(),
            SizedBox(height: AppSpacing.x4),
            _ComingSoonCard(),
          ],
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
                    color: Colors.white.withValues(alpha: 0.16),
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

/// Honest placeholder for the messaging feature the API does not serve yet.
class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.surfacePeach,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  size: 19, color: AppColors.secondary),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.inboxComingTitle,
                      style: AppTypography.subtitle),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.inboxComingBody,
                    style: AppTypography.small
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
