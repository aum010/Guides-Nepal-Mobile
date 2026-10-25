import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/booking.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_repository.dart';
import '../bookings/booking_repository.dart';

/// Upcoming and past bookings for the signed-in traveler. Signed-out
/// travelers get a prompt to sign in rather than an error.
final tripsProvider = FutureProvider.autoDispose<List<Booking>>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isAuthenticated) {
    return Future.value(const <Booking>[]);
  }
  return ref.watch(bookingsProvider.future);
});

/// Trips tab: upcoming and past bookings, driven by real server state.
class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final trips = ref.watch(tripsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenHeader(
              title: AppStrings.navTrips,
              subtitle: trips.maybeWhen(
                data: (list) => _summary(list),
                orElse: () => AppStrings.tripsSubline,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            Expanded(
              child: !auth.isAuthenticated
                  ? EmptyStateView(
                      icon: Icons.card_travel_outlined,
                      title: AppStrings.sessionExpiredTitle,
                      message: AppStrings.sessionExpiredBody,
                      actionLabel: AppStrings.signIn,
                      onAction: () => context.push('/sign-in'),
                    )
                  : trips.when(
                      loading: () => const SkeletonList(itemCount: 3),
                      error: (e, _) => ErrorStateView(
                        message: e is ApiException
                            ? e.message
                            : AppStrings.offlineBody,
                        onRetry: () => ref.invalidate(tripsProvider),
                      ),
                      data: (list) => list.isEmpty
                          ? EmptyStateView(
                              icon: Icons.explore_outlined,
                              title: 'No trips booked yet',
                              message:
                                  'When you book an experience it will show '
                                  'up here so you can track it.',
                              actionLabel: AppStrings.exploreExperiences,
                              onAction: () => context.go('/explore'),
                            )
                          : RefreshIndicator(
                              onRefresh: () async => ref.invalidate(tripsProvider),
                              child: _TripsList(trips: list),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// "2 upcoming · 1 past" — the header states what the list holds before
  /// the traveler scrolls.
  String _summary(List<Booking> list) {
    if (list.isEmpty) return AppStrings.tripsSubline;
    final upcoming = list.where((b) => b.status.canCancel).length;
    final past = list.length - upcoming;
    return [
      if (upcoming > 0) upcoming == 1 ? '1 upcoming' : '$upcoming upcoming',
      if (past > 0) '$past past',
    ].join(' · ');
  }
}

/// Upcoming trips first, finished ones below — one list, two labelled
/// groups, so live trips are never buried under old ones.
class _TripsList extends StatelessWidget {
  const _TripsList({required this.trips});

  final List<Booking> trips;

  @override
  Widget build(BuildContext context) {
    final upcoming = [for (final b in trips) if (b.status.canCancel) b];
    final past = [for (final b in trips) if (!b.status.canCancel) b];

    Widget groupLabel(String label, int count) => Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.x2,
            bottom: AppSpacing.x3,
          ),
          child: Row(
            children: [
              Text(label, style: AppTypography.h3),
              const SizedBox(width: AppSpacing.x2),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x2, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.surfacePeach,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  '$count',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, AppSpacing.x2, AppSpacing.gutter, AppSpacing.x8),
      children: [
        if (upcoming.isNotEmpty) ...[groupLabel(AppStrings.groupUpcoming, upcoming.length)],
        for (final b in upcoming) ...[
          _TripTile(booking: b),
          const SizedBox(height: AppSpacing.x3),
        ],
        if (past.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x2),
          groupLabel(AppStrings.groupPast, past.length),
        ],
        for (final b in past) ...[
          _TripTile(booking: b),
          const SizedBox(height: AppSpacing.x3),
        ],
      ],
    );
  }
}

class _TripTile extends ConsumerStatefulWidget {
  const _TripTile({required this.booking});

  final Booking booking;

  @override
  ConsumerState<_TripTile> createState() => _TripTileState();
}

class _TripTileState extends ConsumerState<_TripTile> {
  // Guards the non-idempotent cancel/archive calls, same as booking submit.
  bool _acting = false;

  Booking get booking => widget.booking;

  Future<void> _run(
    Future<Booking> Function(BookingRepository repo) action,
  ) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action(ref.read(bookingRepositoryProvider));
      // Server state changed — refetch so the tile reflects it.
      ref.invalidate(bookingsProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _confirmAndCancel() async {
    if (_acting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      // Root navigator so the dialog's scrim also dims the nav bar.
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this trip?'),
        content: const Text(
          'Your guide will be notified and the booking will be released. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep trip'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.textOnPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel trip'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run((repo) => repo.cancelBooking(booking.id));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (booking.image != null && booking.image!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: NetworkImageView(
                    url: booking.image,
                    width: 64,
                    height: 64,
                    semanticsLabel: booking.experienceTitle,
                  ),
                )
              else
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surfacePeach,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: const Icon(Icons.landscape_outlined,
                      color: AppColors.secondary),
                ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(booking.experienceTitle, style: AppTypography.subtitle,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    if (booking.city.isNotEmpty)
                      Text(booking.city, style: AppTypography.caption),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              _StatusChip(status: booking.status),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(Formatters.dateWithWeekday(booking.date),
                  style: AppTypography.caption),
              const SizedBox(width: AppSpacing.x4),
              const Icon(Icons.person_outline,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(Formatters.guests(booking.guests),
                  style: AppTypography.caption),
              const Spacer(),
              Text(Formatters.price(booking.price), style: AppTypography.price),
            ],
          ),
          // One action per tile: cancel while the trip is live, archive
          // once it reached a terminal state. Archived trips are left alone.
          if (booking.status.canCancel || booking.status != BookingStatus.archived) ...[
            const SizedBox(height: AppSpacing.x3),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (booking.status.canCancel)
                  AppButton(
                    label: 'Cancel trip',
                    variant: AppButtonVariant.outline,
                    expanded: false,
                    loading: _acting,
                    onPressed: _acting ? null : _confirmAndCancel,
                  )
                else
                  AppButton(
                    label: 'Archive',
                    variant: AppButtonVariant.ghost,
                    expanded: false,
                    loading: _acting,
                    onPressed:
                        _acting ? null : () => _run((repo) => repo.archiveBooking(booking.id)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      BookingStatus.upcoming || BookingStatus.accepted =>
        (AppColors.successSurface, AppColors.success),
      BookingStatus.completed => (AppColors.surfacePeach, AppColors.secondary),
      BookingStatus.cancelled || BookingStatus.rejected =>
        (AppColors.errorSurface, AppColors.error),
      BookingStatus.archived =>
        (AppColors.border, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2 + 2, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: AppTypography.caption
            .copyWith(color: fg, fontWeight: FontWeight.w600, fontSize: 10),
      ),
    );
  }
}
