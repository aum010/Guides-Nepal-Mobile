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
import 'guide_models.dart';
import 'guide_repository.dart';

/// Guide workspace. Reachable only for guide-role sessions — the router
/// redirect bounces travelers to /home, and every endpoint here is
/// `require_role("guide")` and scoped server-side to the signed-in guide.
class GuideShell extends ConsumerWidget {
  const GuideShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    if (!auth.isGuide) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
        ),
        body: const EmptyStateView(
          icon: Icons.lock_outline,
          title: 'Guide tools only',
          message: 'This workspace is available to guide accounts.',
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
          title: Text('Guide dashboard', style: AppTypography.h3),
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.secondary,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Requests'),
              Tab(text: 'Listings'),
              Tab(text: 'Updates'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OverviewTab(),
            _RequestsTab(),
            _ListingsTab(),
            _UpdatesTab(),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(guideDashboardProvider);

    return dashboard.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorStateView(
        message: e is ApiException
            ? e.message
            : 'Sign in as a guide to see your dashboard.',
        onRetry: () => ref.invalidate(guideDashboardProvider),
      ),
      data: (data) {
        final s = data.stats;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(guideDashboardProvider);
            ref.invalidate(guideOnboardingProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            children: [
              const _ProfileCard(),
              const SizedBox(height: AppSpacing.x6),
              _StatGrid(stats: s),
              const SizedBox(height: AppSpacing.x6),
              Text('Your listings', style: AppTypography.h3),
              const SizedBox(height: AppSpacing.x3),
              if (data.listings.isEmpty)
                EmptyStateView(
                  icon: Icons.list_alt_outlined,
                  title: 'No listings yet',
                  message: 'Add an experience listing to describe what you '
                      'offer.',
                  actionLabel: 'Create a listing',
                  onAction: () async {
                    final changed =
                        await context.push<bool>('/guide/listing/new');
                    if (changed == true) {
                      ref.invalidate(guideDashboardProvider);
                    }
                  },
                )
              else
                for (final l in data.listings) ...[
                  _ListingCard(listing: l, onChanged: () =>
                      ref.invalidate(guideDashboardProvider)),
                  const SizedBox(height: AppSpacing.x3),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final GuideStats stats;

  @override
  Widget build(BuildContext context) {
    final cells = <(String, String)>[
      ('Listings', '${stats.listings}'),
      ('Upcoming', '${stats.upcomingBookings}'),
      ('Guests hosted', '${stats.totalGuests}'),
      ('Open spots', '${stats.availableSpots}'),
    ];
    // Two rows of self-sizing cells instead of a fixed-aspect grid: at a
    // 360 dp width (and at larger text scales) an aspect-ratio cell is too
    // short for the value + label and overflows. `IntrinsicHeight` keeps the
    // two cells in a row the same height.
    final rows = [(cells[0], cells[1]), (cells[2], cells[3])];
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: AppSpacing.x3),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatCell(
                    label: rows[r].$1.$1,
                    value: rows[r].$1.$2,
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: _StatCell(
                    label: rows[r].$2.$1,
                    value: rows[r].$2.$2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: AppTypography.h2),
          const SizedBox(height: 2),
          Text(label, style: AppTypography.caption),
        ],
      ),
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(guideBookingsProvider);

    return requests.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorStateView(
        message: e is ApiException ? e.message : AppStrings.offlineBody,
        onRetry: () => ref.invalidate(guideBookingsProvider),
      ),
      data: (list) => list.isEmpty
          ? const EmptyStateView(
              icon: Icons.inbox_outlined,
              title: 'No booking requests',
              message: 'When a traveler books one of your experiences, '
                  'the request shows up here.',
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(guideBookingsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.x3),
                itemBuilder: (_, i) => _RequestTile(request: list[i]),
              ),
            ),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile({required this.request});

  final GuideBookingRequest request;

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _busy = false;

  Future<void> _decide(String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(guideRepositoryProvider)
          .decideBooking(widget.request.id, status);
      ref.invalidate(guideBookingsProvider);
      ref.invalidate(guideDashboardProvider);
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
    final r = widget.request;
    final canDecide = r.status == BookingStatus.upcoming;

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
                child: Text(r.experienceTitle,
                    style: AppTypography.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              BookingStatusChip(status: r.status),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            '${r.travelerName} · ${Formatters.dateShort(r.date)} · '
            '${Formatters.guests(r.guests)} · ${Formatters.price(r.price)}',
            style: AppTypography.caption,
          ),
          if (canDecide) ...[
            const SizedBox(height: AppSpacing.x3),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Accept',
                    loading: _busy,
                    onPressed: () => _decide('accepted'),
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: AppButton(
                    label: 'Decline',
                    variant: AppButtonVariant.outline,
                    loading: _busy,
                    onPressed: () => _decide('rejected'),
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

class _ListingsTab extends ConsumerStatefulWidget {
  const _ListingsTab();

  @override
  ConsumerState<_ListingsTab> createState() => _ListingsTabState();
}

class _ListingsTabState extends ConsumerState<_ListingsTab> {
  late Future<List<GuideListing>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(guideRepositoryProvider).fetchListings();
  }

  void _reload() {
    final next = ref.read(guideRepositoryProvider).fetchListings();
    setState(() {
      _future = next;
    });
  }

  /// Opens the create/edit screen; only reload when the server state
  /// actually changed.
  Future<void> _openEditor([GuideListing? listing]) async {
    final changed = await context.push<bool>(
      listing == null ? '/guide/listing/new' : '/guide/listing/${listing.id}',
    );
    if (changed == true) {
      _reload();
      ref.invalidate(guideDashboardProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: Text('Your listings', style: AppTypography.h3),
              ),
              AppButton(
                label: 'New listing',
                expanded: false,
                onPressed: _openEditor,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<GuideListing>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return ErrorStateView(
                  message: snap.error is ApiException
                      ? (snap.error as ApiException).message
                      : AppStrings.offlineBody,
                  onRetry: _reload,
                );
              }
              final list = snap.data ?? const <GuideListing>[];
              if (list.isEmpty) {
                return EmptyStateView(
                  icon: Icons.list_alt_outlined,
                  title: 'No listings yet',
                  message: 'Add an experience listing to describe what you '
                      'offer.',
                  actionLabel: 'Create a listing',
                  onAction: _openEditor,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.gutter),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.x3),
                  itemBuilder: (_, i) => _ListingCard(
                    listing: list[i],
                    onChanged: _reload,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ListingCard extends ConsumerStatefulWidget {
  const _ListingCard({required this.listing, required this.onChanged});

  final GuideListing listing;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends ConsumerState<_ListingCard> {
  /// Guards the pause/resume PATCH while it is in flight.
  bool _busy = false;

  GuideListing get listing => widget.listing;
  VoidCallback get onChanged => widget.onChanged;

  Future<void> _edit() async {
    final changed =
        await context.push<bool>('/guide/listing/${listing.id}');
    if (changed == true) onChanged();
  }

  /// Pausing hides the listing from travellers without deleting it or its
  /// bookings; resuming puts it back.
  Future<void> _toggleActive() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(guideRepositoryProvider).setListingActive(
            listing.id,
            isActive: !listing.isActive,
          );
      onChanged();
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
              // The photo travellers actually see, so the guide can tell at a
              // glance which listings still need one.
              if (listing.heroImage != null && listing.heroImage!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: NetworkImageView(
                    url: listing.heroImage,
                    width: 56,
                    height: 56,
                    semanticsLabel: 'Photo for ${listing.title}',
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
              ] else ...[
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surfacePeach,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add_photo_alternate_outlined,
                      size: 20, color: AppColors.secondary),
                ),
                const SizedBox(width: AppSpacing.x3),
              ],
              Expanded(
                child: Text(listing.title,
                    style: AppTypography.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              // An active listing is on the public site; saying so is the
              // only way a guide learns their work is bookable, not a draft.
              InfoChip(label: listing.isActive ? 'Live' : 'Paused'),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            '${listing.city} · ${listing.duration} · ${listing.difficulty}',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.x3),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: listing.maxGuests == 0
                        ? 0
                        : listing.bookedGuests / listing.maxGuests,
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    color: AppColors.secondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Text(
                '${listing.bookedGuests}/${listing.maxGuests} booked',
                style: AppTypography.caption,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(Formatters.pricePerPerson(listing.price),
              style: AppTypography.price),
          const SizedBox(height: AppSpacing.x2),
          // Manage actions wrap so they never overflow on a narrow phone.
          Wrap(
            spacing: AppSpacing.x2,
            children: [
              TextButton.icon(
                onPressed: _busy ? null : _edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              TextButton(
                onPressed: _busy ? null : _toggleActive,
                child: Text(listing.isActive ? 'Pause' : 'Resume'),
              ),
              TextButton.icon(
                onPressed: () => _editCapacity(context, ref),
                icon: const Icon(Icons.group_outlined, size: 18),
                label: const Text('Capacity'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editCapacity(BuildContext context, WidgetRef ref) async {
    final controller =
        TextEditingController(text: '${listing.maxGuests}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Maximum guests'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. 10'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text)),
            child: const Text(AppStrings.save),
          ),
        ],
      ),
    );
    if (result == null || result < 1) return;

    try {
      await ref
          .read(guideRepositoryProvider)
          .updateListingCapacity(listing.id, maxGuests: result);
      onChanged();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

/// Setup prompt / summary for the guide's own profile
/// (`GET /guide/onboarding`).
///
/// The server stores `onboarding_completed` as a claim the guide makes, so the
/// card prompts whenever the claim is missing *or* the details a complete
/// profile needs are no longer filled in.
class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final changed = await context.push<bool>('/guide/profile');
    if (changed == true) {
      ref.invalidate(guideOnboardingProvider);
      ref.invalidate(guideDashboardProvider);
    }
  }

  /// `['a name', 'a city']` → `'a name and a city'`; long lists are summed up
  /// instead of read out.
  static String _describe(List<String> missing) {
    if (missing.length > 3) return 'Add your details so your account is ready to host.';
    if (missing.length == 1) return 'Add ${missing.single}.';
    if (missing.length == 2) return 'Add ${missing[0]} and ${missing[1]}.';
    return 'Add ${missing.sublist(0, missing.length - 1).join(', ')} and '
        '${missing.last}.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(guideOnboardingProvider);

    return profile.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => _Shell(
        background: AppColors.surface,
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Text(
                e is ApiException ? e.message : 'Could not load your profile.',
                style: AppTypography.caption,
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(guideOnboardingProvider),
              child: const Text(AppStrings.retry),
            ),
          ],
        ),
      ),
      data: (data) {
        final draft = GuideProfileDraft.fromProfile(data);
        final missing = draft.missingForCompletion();
        final ready = data.onboardingCompleted && missing.isEmpty;

        if (ready) {
          return _Shell(
            background: AppColors.surface,
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined,
                    color: AppColors.success),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Profile complete', style: AppTypography.subtitle),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (draft.displayName.isNotEmpty) draft.displayName,
                          if (draft.cities.isNotEmpty)
                            draft.cities.join(' · '),
                        ].join(' · '),
                        style: AppTypography.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _open(context, ref),
                  child: const Text('Edit'),
                ),
              ],
            ),
          );
        }

        return _Shell(
          background: AppColors.surfacePeach,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline, color: AppColors.secondary),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: Text(
                      'Finish your guide profile',
                      style: AppTypography.subtitle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(_describe(missing), style: AppTypography.caption),
              const SizedBox(height: AppSpacing.x3),
              AppButton(
                label: 'Complete profile',
                expanded: false,
                onPressed: () => _open(context, ref),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shared card container for the profile prompt.
class _Shell extends StatelessWidget {
  const _Shell({required this.child, required this.background});

  final Widget child;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// Guide updates (`GET /guide/status`) and the composer entry point.
class _UpdatesTab extends ConsumerWidget {
  const _UpdatesTab();

  Future<void> _compose(BuildContext context, WidgetRef ref) async {
    final posted = await context.push<bool>('/guide/status/new');
    if (posted == true) ref.invalidate(guideStatusProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updates = ref.watch(guideStatusProvider);
    // Listing ids → titles for the card subtitle. A listings failure only
    // costs that line; the updates themselves still render.
    final titles = {
      for (final l in ref.watch(guideListingsProvider).valueOrNull ??
          const <GuideListing>[])
        l.id: l.title,
    };

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
              Expanded(child: Text('Updates', style: AppTypography.h3)),
              AppButton(
                label: 'Post update',
                expanded: false,
                onPressed: () => _compose(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: updates.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorStateView(
              message: e is ApiException ? e.message : AppStrings.offlineBody,
              onRetry: () => ref.invalidate(guideStatusProvider),
            ),
            data: (list) => list.isEmpty
                ? EmptyStateView(
                    icon: Icons.campaign_outlined,
                    title: 'No updates yet',
                    message: 'Post an announcement, a schedule change or a '
                        'capacity note for your experiences.',
                    actionLabel: 'Post an update',
                    onAction: () => _compose(context, ref),
                  )
                : RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(guideStatusProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.gutter),
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.x3),
                      itemBuilder: (_, i) => _StatusCard(
                        update: list[i],
                        listingTitle: titles[list[i].listingId],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends ConsumerStatefulWidget {
  const _StatusCard({required this.update, this.listingTitle});

  final GuideStatusUpdate update;
  final String? listingTitle;

  @override
  ConsumerState<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends ConsumerState<_StatusCard> {
  /// Guards the delete request while it is in flight.
  bool _deleting = false;

  GuideStatusUpdate get update => widget.update;

  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this update?'),
        content: const Text(
          'It disappears from your updates. Bookings are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(guideRepositoryProvider).deleteStatusUpdate(update.id);
      ref.invalidate(guideStatusProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// `All experiences` plus whatever detail the update carries.
  String get _subtitle {
    final parts = <String>[widget.listingTitle ?? 'All experiences'];
    final area = update.area?.trim() ?? '';
    if (area.isNotEmpty) parts.add(area);
    if (update.eventDate != null) {
      parts.add(Formatters.dateShort(update.eventDate!));
    }
    if (update.currentCapacity != null && update.maxCapacity != null) {
      parts.add('${update.currentCapacity}/${update.maxCapacity} spots');
    }
    final created = update.createdAt;
    if (created != null) parts.add(Formatters.relativeTime(created));
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x4,
        AppSpacing.x3,
        AppSpacing.x2,
        AppSpacing.x4,
      ),
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
              InfoChip(label: update.typeLabel),
              if (!update.isActive) ...[
                const SizedBox(width: AppSpacing.x2),
                const InfoChip(label: 'Hidden'),
              ],
              const Spacer(),
              IconButton(
                tooltip: 'Delete update',
                onPressed: _deleting ? null : _delete,
                icon: _deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline, size: 20),
                color: AppColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x1),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.x3),
            child: Text(
              update.message,
              style: AppTypography.body,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(_subtitle, style: AppTypography.caption),
        ],
      ),
    );
  }
}
