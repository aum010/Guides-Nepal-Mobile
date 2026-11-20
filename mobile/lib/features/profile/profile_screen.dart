import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_repository.dart';

/// Profile tab: identity, saved list, and account actions.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: auth.isAuthenticated
            ? ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter,
                    AppSpacing.x4, AppSpacing.gutter, AppSpacing.x8),
                children: [
                  Row(
                    children: [
                      // A warm ring lifts the avatar off the cream canvas
                      // without introducing another shadow level.
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.peach, AppColors.surfacePeach],
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 29,
                          backgroundColor: AppColors.surface,
                          foregroundImage:
                              (user?.avatarUrl?.isNotEmpty ?? false)
                                  ? NetworkImage(user!.avatarUrl!)
                                  : null,
                          child: Text(
                            user?.initials ?? '?',
                            style: AppTypography.h2
                                .copyWith(color: AppColors.secondary),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? '',
                              style: AppTypography.h2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? '',
                              style: AppTypography.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Editing lives on the identity itself, where a traveler
                      // looks when the name or photo is wrong.
                      IconButton(
                        tooltip: AppStrings.editProfile,
                        icon: const Icon(Icons.edit_outlined,
                            size: 20, color: AppColors.secondary),
                        onPressed: () => context.push('/profile/edit'),
                      ),
                    ],
                  ),
                  if (user != null &&
                      ((user.phone?.isNotEmpty ?? false) ||
                          (user.bio?.isNotEmpty ?? false))) ...[
                    const SizedBox(height: AppSpacing.x3),
                    if (user.phone?.isNotEmpty ?? false)
                      Row(
                        children: [
                          const Icon(Icons.call_outlined,
                              size: 15, color: AppColors.textTertiary),
                          const SizedBox(width: 6),
                          Text(
                            user.phone!,
                            style: AppTypography.small.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    if (user.bio?.isNotEmpty ?? false) ...[
                      const SizedBox(height: AppSpacing.x1),
                      Text(
                        user.bio!,
                        style: AppTypography.small.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.x6),
                  const _SectionLabel(AppStrings.sectionYourActivity),
                  _ActionTile(
                    icon: Icons.favorite_outline,
                    title: AppStrings.navSaved,
                    subtitle: 'Experiences you have saved',
                    onTap: () => context.push('/saved'),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  _ActionTile(
                    icon: Icons.card_travel_outlined,
                    title: AppStrings.navTrips,
                    subtitle: 'Your bookings and trips',
                    onTap: () => context.go('/trips'),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  const _SectionLabel(AppStrings.sectionPlanSupport),
                  _ActionTile(
                    icon: Icons.smart_toy_outlined,
                    title: AppStrings.mailaDai,
                    subtitle: 'Ask your local travel assistant',
                    onTap: () => context.push('/ai'),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  _ActionTile(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & FAQ',
                    subtitle: 'How bookings, guides and updates work',
                    onTap: () => context.push('/faq'),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  _ActionTile(
                    icon: Icons.mail_outline_rounded,
                    title: 'Contact us',
                    subtitle: 'Reach the support team',
                    onTap: () => context.push('/contact'),
                  ),
                  if (auth.isHost) ...[
                    const SizedBox(height: AppSpacing.x6),
                    const _SectionLabel(AppStrings.sectionHostTools),
                    _ActionTile(
                      icon: Icons.home_work_outlined,
                      title: AppStrings.hostDashboard,
                      subtitle: AppStrings.hostToolsSubtitle,
                      onTap: () => context.push('/host'),
                    ),
                  ],
                  if (auth.isGuide) ...[
                    const SizedBox(height: AppSpacing.x6),
                    const _SectionLabel(AppStrings.sectionGuideTools),
                    _ActionTile(
                      icon: Icons.dashboard_outlined,
                      title: 'Guide dashboard',
                      subtitle: 'Manage listings and booking requests',
                      onTap: () => context.push('/guide'),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    _ActionTile(
                      icon: Icons.badge_outlined,
                      title: 'Guide profile',
                      subtitle: 'Your name, expertise, cities and languages',
                      onTap: () => context.push('/guide/profile'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.x6),
                  const _SectionLabel(AppStrings.sectionAccount),
                  _ActionTile(
                    icon: Icons.lock_reset_outlined,
                    title: AppStrings.changePassword,
                    subtitle: AppStrings.changePasswordSubtitle,
                    onTap: () => context.push('/settings/password'),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  AppButton(
                    label: AppStrings.signOut,
                    variant: AppButtonVariant.outline,
                    onPressed: () => _confirmSignOut(context, ref),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  TextButton(
                    onPressed: () => _confirmSignOutEverywhere(context, ref),
                    child: Text(
                      'Sign out of all devices',
                      style: AppTypography.label
                          .copyWith(color: AppColors.secondary),
                    ),
                  ),
                ],
              )
            : EmptyStateView(
                icon: Icons.person_outline,
                title: 'Sign in to your account',
                message: 'Sign in to see your saved experiences and trips.',
                actionLabel: AppStrings.signIn,
                onAction: () => context.push('/sign-in'),
              ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      // Root navigator so the dialog's scrim also dims the nav bar.
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.signOut),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(AppStrings.signOut),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).signOut();
      if (context.mounted) context.go('/sign-in');
    }
  }

  Future<void> _confirmSignOutEverywhere(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out everywhere'),
        content: const Text(
          'This ends your session on every device, including this one, and '
          'revokes every sign-in token. You will need to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out everywhere'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).signOutEverywhere();
      if (context.mounted) context.go('/sign-in');
    }
  }
}

/// Small caps label that opens a group of settings rows.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x2),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.eyebrow.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.x4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.secondary),
              const SizedBox(width: AppSpacing.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.subtitle),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTypography.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
