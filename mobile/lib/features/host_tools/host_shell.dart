import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_repository.dart';
import 'host_models.dart';
import 'host_repository.dart';

/// Host workspace for the self-registerable `host` role.
///
/// Deliberately separate from the guide workspace: hosts and guides are
/// different roles in `backend/app/core/roles.py`, they own different records,
/// and `/host/*` answers 403 to any other role. The router bounces non-hosts to
/// /home; the server enforces the same rule again on every request.
class HostShell extends ConsumerWidget {
  const HostShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    if (!auth.isHost) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
        ),
        body: const EmptyStateView(
          icon: Icons.lock_outline,
          title: AppStrings.hostWorkspaceOnlyTitle,
          message: AppStrings.hostWorkspaceOnlyBody,
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
          title: Text(AppStrings.hostDashboard, style: AppTypography.h3),
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.secondary,
            tabs: [
              Tab(text: AppStrings.hostTabExperiences),
              Tab(text: AppStrings.hostTabTours),
              Tab(text: AppStrings.hostTabBookings),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ExperiencesTab(),
            _ToursTab(),
            _BookingsTab(),
          ],
        ),
      ),
    );
  }
}

// --- Experiences -----------------------------------------------------------

class _ExperiencesTab extends ConsumerWidget {
  const _ExperiencesTab();

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      [HostExperience? experience]) async {
    final changed = await context.push<bool>(
      experience == null
          ? '/host/experience/new'
          : '/host/experience/${experience.id}',
    );
    if (changed == true) ref.invalidate(hostExperiencesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final experiences = ref.watch(hostExperiencesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.x3,
            AppSpacing.gutter,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.hostExperiencesTitle,
                  style: AppTypography.h3,
                ),
              ),
              AppButton(
                label: AppStrings.hostNewExperience,
                expanded: false,
                onPressed: () => _openEditor(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: experiences.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorStateView(
              message: e is ApiException ? e.message : AppStrings.offlineBody,
              onRetry: () => ref.invalidate(hostExperiencesProvider),
            ),
            data: (list) => list.isEmpty
                ? EmptyStateView(
                    icon: Icons.travel_explore_outlined,
                    title: AppStrings.hostNoExperiencesTitle,
                    message: AppStrings.hostNoExperiencesBody,
                    actionLabel: AppStrings.hostNewExperience,
                    onAction: () => _openEditor(context, ref),
                  )
                : RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(hostExperiencesProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.gutter),
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.x3),
                      itemBuilder: (_, i) => _ExperienceCard(
                        experience: list[i],
                        onChanged: () =>
                            ref.invalidate(hostExperiencesProvider),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ExperienceCard extends ConsumerStatefulWidget {
  const _ExperienceCard({required this.experience, required this.onChanged});

  final HostExperience experience;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ExperienceCard> createState() => _ExperienceCardState();
}

class _ExperienceCardState extends ConsumerState<_ExperienceCard> {
  bool _busy = false;

  HostExperience get experience => widget.experience;

  Future<void> _edit() async {
    final changed =
        await context.push<bool>('/host/experience/${experience.id}');
    if (changed == true) widget.onChanged();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.hostDeleteExperienceTitle),
        content: const Text(AppStrings.hostDeleteExperienceBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(AppStrings.hostKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(AppStrings.hostDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(hostRepositoryProvider)
          .deleteExperience(experience.id);
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.hostExperienceDeleted)),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = [
      experience.city,
      experience.category,
      experience.duration,
    ].where((part) => part.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  experience.title,
                  style: AppTypography.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // The response carries `is_active`, and no host endpoint can
              // change it — so it is reported, never offered as a toggle.
              InfoChip(
                label: experience.isActive
                    ? AppStrings.hostActive
                    : AppStrings.hostInactive,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(meta, style: AppTypography.caption),
          const SizedBox(height: AppSpacing.x2),
          Text(
            Formatters.pricePerPerson(experience.price),
            style: AppTypography.price,
          ),
          const SizedBox(height: AppSpacing.x2),
          Wrap(
            spacing: AppSpacing.x2,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : _edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text(AppStrings.hostEditExperience),
              ),
              TextButton(
                onPressed: _busy ? null : _delete,
                child: const Text(AppStrings.hostDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Tours -----------------------------------------------------------------

class _ToursTab extends ConsumerWidget {
  const _ToursTab();

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      [HostTour? tour]) async {
    final changed = await context.push<bool>(
      tour == null ? '/host/tour/new' : '/host/tour/${tour.id}',
    );
    if (changed == true) ref.invalidate(hostToursProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tours = ref.watch(hostToursProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.x3,
            AppSpacing.gutter,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child:
                    Text(AppStrings.hostToursTitle, style: AppTypography.h3),
              ),
              AppButton(
                label: AppStrings.hostNewTour,
                expanded: false,
                onPressed: () => _openEditor(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: tours.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorStateView(
              message: e is ApiException ? e.message : AppStrings.offlineBody,
              onRetry: () => ref.invalidate(hostToursProvider),
            ),
            data: (list) => list.isEmpty
                ? EmptyStateView(
                    icon: Icons.route_outlined,
                    title: AppStrings.hostNoToursTitle,
                    message: AppStrings.hostNoToursBody,
                    actionLabel: AppStrings.hostNewTour,
                    onAction: () => _openEditor(context, ref),
                  )
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(hostToursProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.gutter),
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.x3),
                      itemBuilder: (_, i) => _TourCard(
                        tour: list[i],
                        onChanged: () => ref.invalidate(hostToursProvider),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _TourCard extends ConsumerStatefulWidget {
  const _TourCard({required this.tour, required this.onChanged});

  final HostTour tour;
  final VoidCallback onChanged;

  @override
  ConsumerState<_TourCard> createState() => _TourCardState();
}

class _TourCardState extends ConsumerState<_TourCard> {
  bool _busy = false;

  HostTour get tour => widget.tour;

  Future<void> _edit() async {
    final changed = await context.push<bool>('/host/tour/${tour.id}');
    if (changed == true) widget.onChanged();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.hostDeleteTourTitle),
        content: const Text(AppStrings.hostDeleteTourBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(AppStrings.hostKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(AppStrings.hostDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(hostRepositoryProvider).deleteTour(tour.id);
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.hostTourDeleted)),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = [
      tour.city,
      tour.duration,
      tour.difficulty,
      Formatters.guests(tour.maxGuests),
    ].where((part) => part.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  tour.title,
                  style: AppTypography.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InfoChip(
                label: tour.isActive
                    ? AppStrings.hostActive
                    : AppStrings.hostInactive,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(meta, style: AppTypography.caption),
          const SizedBox(height: AppSpacing.x2),
          Text(
            Formatters.pricePerPerson(tour.price),
            style: AppTypography.price,
          ),
          const SizedBox(height: AppSpacing.x2),
          Wrap(
            spacing: AppSpacing.x2,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : _edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text(AppStrings.hostEditTour),
              ),
              TextButton(
                onPressed: _busy ? null : _delete,
                child: const Text(AppStrings.hostDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Bookings --------------------------------------------------------------

class _BookingsTab extends ConsumerWidget {
  const _BookingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(hostBookingsProvider);

    return bookings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorStateView(
        message: e is ApiException ? e.message : AppStrings.offlineBody,
        onRetry: () => ref.invalidate(hostBookingsProvider),
      ),
      data: (list) => list.isEmpty
          ? const EmptyStateView(
              icon: Icons.inbox_outlined,
              title: AppStrings.hostNoBookingsTitle,
              message: AppStrings.hostNoBookingsBody,
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(hostBookingsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.x3),
                itemBuilder: (_, i) => _BookingCard(
                  booking: list[i],
                  onChanged: () => ref.invalidate(hostBookingsProvider),
                ),
              ),
            ),
    );
  }
}

class _BookingCard extends ConsumerStatefulWidget {
  const _BookingCard({required this.booking, required this.onChanged});

  final HostBooking booking;
  final VoidCallback onChanged;

  @override
  ConsumerState<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends ConsumerState<_BookingCard> {
  bool _busy = false;

  HostBooking get booking => widget.booking;

  Future<void> _decide({required bool accept}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(hostRepositoryProvider)
          .decideBooking(booking.id, accept: accept);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = [
      Formatters.dateShort(booking.date),
      Formatters.guests(booking.guests),
      Formatters.price(booking.totalPrice),
    ].join(' · ');
    final contact = [
      booking.guestEmail,
      if (booking.guestPhone != null) booking.guestPhone!,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.experienceTitle,
                  style: AppTypography.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              BookingStatusChip(status: booking.status),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(booking.guestName, style: AppTypography.bodyMedium),
          const SizedBox(height: 2),
          Text(contact, style: AppTypography.caption),
          const SizedBox(height: AppSpacing.x2),
          Text(meta, style: AppTypography.caption),
          if (booking.notes != null) ...[
            const SizedBox(height: AppSpacing.x2),
            Text(booking.notes!, style: AppTypography.small),
          ],
          if (booking.canDecide) ...[
            const SizedBox(height: AppSpacing.x3),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: AppStrings.hostAccept,
                    loading: _busy,
                    onPressed: () => _decide(accept: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: AppButton(
                    label: AppStrings.hostDecline,
                    variant: AppButtonVariant.outline,
                    loading: _busy,
                    onPressed: () => _decide(accept: false),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
