import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/widgets.dart';
import 'guide_models.dart';
import 'guide_repository.dart';

/// Compose one guide update (`POST /guide/status`): an announcement, an
/// availability or schedule note, or a capacity change.
///
/// The two type-specific field groups mirror the schema: capacity numbers are
/// only meaningful for `capacity`, the date only for `schedule`. The listing
/// picker is optional — an update without one applies to everything the guide
/// offers — and the server rejects a listing id the guide does not own, which
/// is surfaced inline. Pops with `true` once the update is stored.
class GuideStatusComposerScreen extends ConsumerStatefulWidget {
  const GuideStatusComposerScreen({super.key});

  @override
  ConsumerState<GuideStatusComposerScreen> createState() =>
      _GuideStatusComposerScreenState();
}

class _GuideStatusComposerScreenState
    extends ConsumerState<GuideStatusComposerScreen> {
  final _message = TextEditingController();
  final _area = TextEditingController();
  final _currentCapacity = TextEditingController();
  final _maxCapacity = TextEditingController();

  String _type = 'announcement';
  int? _listingId;
  DateTime? _eventDate;

  bool _saving = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    for (final c in [_message, _area, _currentCapacity, _maxCapacity]) {
      c.dispose();
    }
    super.dispose();
  }

  GuideStatusDraft _draft() => GuideStatusDraft(
        updateType: _type,
        message: _message.text,
        listingId: _listingId,
        area: _area.text,
        eventDate: _eventDate,
        currentCapacityText: _currentCapacity.text,
        maxCapacityText: _maxCapacity.text,
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (picked != null && mounted) {
      setState(() => _eventDate = picked);
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    final draft = _draft();
    final errors = draft.validate();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }

    setState(() {
      _errors = const {};
      _saving = true;
    });
    try {
      await ref.read(guideRepositoryProvider).postStatusUpdate(draft);
      ref.invalidate(guideStatusProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Keep the text: a rejected listing link or message can be fixed.
      setState(() => _errors = _serverFieldErrors(e));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Server field names → this form's field names.
  static Map<String, String> _serverFieldErrors(ApiException e) {
    const names = {
      'update_type': 'updateType',
      'message': 'message',
      'listing_id': 'listingId',
      'area': 'area',
      'event_date': 'eventDate',
      'current_capacity': 'currentCapacity',
      'max_capacity': 'maxCapacity',
    };
    final out = <String, String>{};
    e.fieldErrors.forEach((field, message) {
      final key = names[field];
      if (key != null) out[key] = message;
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final listings = ref.watch(guideListingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        title: Text('Post an update', style: AppTypography.h3),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.x2,
          AppSpacing.gutter,
          AppSpacing.x10,
        ),
        children: [
          Text(
            'Updates are saved to your account. They are not shown to '
            'travellers yet.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.x4),
          _ChipGroup(
            label: 'What kind of update is it?',
            options: [
              for (final t in GuideStatusUpdate.types)
                (t, '${t[0].toUpperCase()}${t.substring(1)}'),
            ],
            selected: _type,
            errorText: _errors['updateType'],
            onSelected: (v) => setState(() {
              _type = v;
              // Hidden fields keep their text but are never sent for another
              // update type (see `GuideStatusDraft.toJson`).
              _errors = const {};
            }),
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            key: const ValueKey('status-message'),
            label: 'Update',
            hint: 'Tomorrow’s Sarangkot sunrise starts at 5:30 am — the ridge '
                'is foggy until then.',
            controller: _message,
            errorText: _errors['message'],
            maxLines: 5,
          ),
          const SizedBox(height: AppSpacing.x4),
          _listingPicker(listings),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            key: const ValueKey('status-area'),
            label: 'Area (optional)',
            hint: 'Lakeside',
            controller: _area,
            errorText: _errors['area'],
            textInputAction: TextInputAction.next,
          ),
          if (_type == 'schedule') ...[
            const SizedBox(height: AppSpacing.x4),
            _DateField(
              date: _eventDate,
              errorText: _errors['eventDate'],
              onTap: _pickDate,
            ),
          ],
          if (_type == 'capacity') ...[
            const SizedBox(height: AppSpacing.x4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    key: const ValueKey('status-current-capacity'),
                    label: 'Spots booked',
                    hint: '6',
                    controller: _currentCapacity,
                    errorText: _errors['currentCapacity'],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: AppTextField(
                    key: const ValueKey('status-max-capacity'),
                    label: 'Total spots',
                    hint: '10',
                    controller: _maxCapacity,
                    errorText: _errors['maxCapacity'],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.done,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.x6),
          AppButton(
            label: 'Post update',
            loading: _saving,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  /// `null` (= all experiences) plus the guide's own listings. If the list
  /// cannot be loaded the update can still be posted guide-wide.
  Widget _listingPicker(AsyncValue<List<GuideListing>> listings) {
    return listings.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.x2),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Which experience?', style: AppTypography.label),
          const SizedBox(height: 6),
          Text(
            'Your listings could not be loaded, so this update covers '
            'everything you offer.',
            style: AppTypography.caption,
          ),
          TextButton(
            onPressed: () => ref.invalidate(guideListingsProvider),
            child: const Text(AppStrings.retry),
          ),
        ],
      ),
      data: (list) => _ChipGroup(
        label: 'Which experience?',
        options: [
          ('', 'All experiences'),
          for (final l in list) ('${l.id}', l.title),
        ],
        selected: _listingId == null ? '' : '$_listingId',
        errorText: _errors['listingId'],
        onSelected: (v) => setState(() {
          _listingId = v.isEmpty ? null : int.parse(v);
        }),
      ),
    );
  }
}

/// A labeled single-select chip row over `(value, label)` pairs.
class _ChipGroup extends StatelessWidget {
  const _ChipGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.errorText,
  });

  final String label;
  final List<(String, String)> options;
  final String? selected;
  final ValueChanged<String> onSelected;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label),
        const SizedBox(height: 6),
        Wrap(
          spacing: AppSpacing.x2,
          runSpacing: AppSpacing.x2,
          children: [
            for (final (value, text) in options)
              AppFilterChip(
                label: text,
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

/// Tappable date row for `schedule` updates.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.onTap,
    this.errorText,
  });

  final DateTime? date;
  final VoidCallback onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Date it applies to', style: AppTypography.label),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('status-date'),
            onPressed: onTap,
            icon: const Icon(Icons.event_outlined, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              alignment: Alignment.centerLeft,
              minimumSize: const Size(
                AppSpacing.minTouchTarget,
                AppSpacing.minTouchTarget,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
            label: Text(
              date == null
                  ? 'Choose date'
                  : Formatters.dateWithWeekday(date!),
              style: AppTypography.body,
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}
