import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../features/experiences/experience_repository.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/city_update.dart';

/// Traveller-facing "what's happening here" feed for one city.
///
/// Shown on destination and experience pages, both of which are keyed by a
/// city. Updates are posted by guides from their own workspace and reach
/// travellers through `GET /updates?city=…`; the feed never exposes anything
/// beyond a guide's chosen display name and their update text.
///
/// Unlike most secondary sections this one **does** show a retry on failure:
/// the feed carries things that change a day out — a closed trail, a moved
/// pick-up — so swallowing the error would hide information a traveller may
/// be acting on.
class CityUpdatesSection extends ConsumerWidget {
  const CityUpdatesSection({
    super.key,
    required this.city,
    this.title = 'Local updates',
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
  });

  final String city;

  /// Section heading. Pass `null` when the caller renders its own header
  /// above the feed (Home does, because its header also carries the city
  /// picker and must stay visible when the feed is empty).
  final String? title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updates = ref.watch(cityUpdatesProvider(city));

    return updates.when(
      // A feed that has not arrived yet is not worth reserving space for.
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: padding,
        child: Row(
          children: [
            const Icon(Icons.sync_problem_outlined,
                size: 18, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Text(
                e is ApiException
                    ? 'Local updates could not be loaded.'
                    : AppStrings.offlineBody,
                style: AppTypography.caption,
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(cityUpdatesProvider(city)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      // An empty feed is normal and unremarkable, so it renders nothing.
      data: (list) => list.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(title!, style: AppTypography.h3),
                    const SizedBox(height: AppSpacing.x3),
                  ],
                  for (final update in list) ...[
                    _UpdateCard(update: update),
                    const SizedBox(height: AppSpacing.x3),
                  ],
                ],
              ),
            ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.update});

  final CityUpdate update;

  /// `Sunrise hike · Lakeside · 3 h ago` — only the parts that exist.
  String get _meta {
    final parts = <String>[
      if (update.listingTitle != null) update.listingTitle!,
      if (update.area != null && update.area!.trim().isNotEmpty)
        update.area!.trim(),
      if (update.eventDate != null) Formatters.dateWithWeekday(update.eventDate!),
      update.capacityLabel ?? '',
      if (update.createdAt != null) Formatters.relativeTime(update.createdAt!),
    ]..removeWhere((part) => part.isEmpty);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: AppColors.surfacePeach,
                child: Text(
                  _guideInitials,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x2 + 2),
              Expanded(
                child: Text(
                  update.guideName,
                  style: AppTypography.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x2 + 2,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfacePeach,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  update.typeLabel,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(update.message, style: AppTypography.body),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.x2),
            Text(meta, style: AppTypography.caption),
          ],
        ],
      ),
    );
  }

  String get _guideInitials {
    final parts =
        update.guideName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '·';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
