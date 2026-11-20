import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/inbox/inbox_repository.dart';
import '../l10n/app_strings.dart';
import '../shared/widgets/floating_nav_bar.dart';

/// Bottom-navigation shell hosting the five primary destinations. The
/// Maila Dai assistant is reachable from the Home app bar so it never
/// permanently occupies a tab slot.
///
/// The Inbox tab carries the unread badge: it reads the same conversation
/// list the Inbox screen shows, and refreshes when the traveller switches
/// tabs so the count is never stale after leaving a thread.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadMessagesProvider);

    return Scaffold(
      body: shell,
      // Tab content scrolls beneath the floating pill bar; Scaffold pads
      // each screen's SafeArea so nothing interactive hides under it.
      extendBody: true,
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) {
          // Entering the inbox is the moment its count must be exact.
          if (index == 3) ref.invalidate(conversationsProvider);
          shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          );
        },
        items: [
          const FloatingNavItem(
            icon: Icons.explore_outlined,
            selectedIcon: Icons.explore,
            label: AppStrings.navHome,
          ),
          const FloatingNavItem(
            icon: Icons.search_outlined,
            selectedIcon: Icons.search_rounded,
            label: AppStrings.navExplore,
          ),
          const FloatingNavItem(
            icon: Icons.card_travel_outlined,
            selectedIcon: Icons.card_travel_rounded,
            label: AppStrings.navTrips,
          ),
          FloatingNavItem(
            icon: Icons.chat_bubble_outline_rounded,
            selectedIcon: Icons.chat_bubble_rounded,
            label: AppStrings.navInbox,
            badgeCount: unread,
          ),
          const FloatingNavItem(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: AppStrings.navProfile,
          ),
        ],
      ),
    );
  }
}
