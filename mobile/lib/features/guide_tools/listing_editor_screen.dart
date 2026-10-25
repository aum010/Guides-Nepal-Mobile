import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/widgets.dart';
import 'guide_models.dart';
import 'guide_repository.dart';

/// Create (`POST /guide/listings`) or edit (`PATCH /guide/listings/{id}`) one
/// of the signed-in guide's own listings, and delete it.
///
/// Fields and validation mirror the server schema, so the common mistakes are
/// caught without a round trip; anything the server rejects is still surfaced
/// inline and in a snackbar. Pops with `true` when the server state changed so
/// the caller can reload its lists.
class ListingEditorScreen extends ConsumerStatefulWidget {
  const ListingEditorScreen({super.key, this.listingId});

  /// `null` creates a new listing.
  final int? listingId;

  @override
  ConsumerState<ListingEditorScreen> createState() =>
      _ListingEditorScreenState();
}

class _ListingEditorScreenState extends ConsumerState<ListingEditorScreen> {
  final _title = TextEditingController();
  final _city = TextEditingController();
  final _area = TextEditingController();
  final _description = TextEditingController();
  final _itinerary = TextEditingController();
  final _meetingPoint = TextEditingController();
  final _duration = TextEditingController();
  final _price = TextEditingController();
  final _maxGuests = TextEditingController(text: '10');

  String _category = 'tour';
  String _difficulty = 'Easy';
  bool _isActive = true;

  bool _loading = false;
  String? _loadError;
  bool _saving = false;
  bool _deleting = false;
  Map<String, String> _errors = const {};

  /// Difficulties offered as chips. A listing may already carry a value the
  /// app does not offer (the field is free text server-side); it is kept as a
  /// chip so editing never silently rewrites it.
  List<String> _difficultyChoices = ListingDraft.difficulties;

  bool get _isEditing => widget.listingId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _load();
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _city,
      _area,
      _description,
      _itinerary,
      _meetingPoint,
      _duration,
      _price,
      _maxGuests,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The editor is reachable from a cold deep link, so the listing is loaded
  /// from the guide's own list rather than handed over through router `extra`.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final listings = await ref.read(guideRepositoryProvider).fetchListings();
      if (!mounted) return;
      final matches = listings.where((l) => l.id == widget.listingId);
      if (matches.isEmpty) {
        setState(() {
          _loading = false;
          _loadError = 'This listing is no longer available.';
        });
        return;
      }
      final listing = matches.first;
      final draft = ListingDraft.fromListing(listing);
      _title.text = draft.title;
      _city.text = draft.city;
      _area.text = draft.area;
      _description.text = draft.description;
      _itinerary.text = draft.itinerary;
      _meetingPoint.text = draft.meetingPoint;
      _duration.text = draft.duration;
      _price.text = draft.priceText;
      _maxGuests.text = draft.maxGuestsText;
      setState(() {
        _category = draft.category;
        _isActive = draft.isActive;
        _difficulty = draft.difficulty;
        _difficultyChoices = [
          if (draft.difficulty.isNotEmpty &&
              !ListingDraft.difficulties.contains(draft.difficulty))
            draft.difficulty,
          ...ListingDraft.difficulties,
        ];
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  ListingDraft _draft() => ListingDraft(
        title: _title.text,
        category: _category,
        city: _city.text,
        area: _area.text,
        description: _description.text,
        itinerary: _itinerary.text,
        meetingPoint: _meetingPoint.text,
        duration: _duration.text,
        difficulty: _difficulty,
        priceText: _price.text,
        maxGuestsText: _maxGuests.text,
        isActive: _isActive,
      );

  Future<void> _save() async {
    if (_saving || _deleting) return;
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
      final repo = ref.read(guideRepositoryProvider);
      if (_isEditing) {
        await repo.updateListing(widget.listingId!, draft);
      } else {
        await repo.createListing(draft);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = _serverFieldErrors(e));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    if (_saving || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: const Text(
          'Travellers will no longer be able to find or book it. Trips '
          'already booked are not affected. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep listing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.textOnPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(guideRepositoryProvider).deleteListing(widget.listingId!);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// Server field names → this form's field names.
  static Map<String, String> _serverFieldErrors(ApiException e) {
    const names = {
      'title': 'title',
      'category': 'category',
      'city': 'city',
      'area': 'area',
      'description': 'description',
      'itinerary': 'itinerary',
      'meeting_point': 'meetingPoint',
      'duration': 'duration',
      'difficulty': 'difficulty',
      'price': 'price',
      'max_guests': 'maxGuests',
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          _isEditing ? 'Edit listing' : 'New listing',
          style: AppTypography.h3,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorStateView(message: _loadError!, onRetry: _load)
              : _form(),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.x2,
        AppSpacing.gutter,
        AppSpacing.x10,
      ),
      children: [
        Text(
          _isEditing
              ? 'Changes are live as soon as you save.'
              : 'Tell travellers what you offer, where it starts and what it '
                  'costs.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.x4),
        AppTextField(
          key: const ValueKey('listing-title'),
          label: 'Title',
          hint: 'Sunrise hike to Sarangkot',
          controller: _title,
          errorText: _errors['title'],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.x4),
        _ChoiceGroup(
          label: 'Category',
          options: ListingDraft.categories,
          selected: _category,
          errorText: _errors['category'],
          onSelected: (v) => setState(() => _category = v),
        ),
        const SizedBox(height: AppSpacing.x4),
        AppTextField(
          key: const ValueKey('listing-city'),
          label: 'City',
          hint: 'Pokhara',
          controller: _city,
          errorText: _errors['city'],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.x4),
        AppTextField(
          key: const ValueKey('listing-area'),
          label: 'Area (optional)',
          hint: 'Lakeside',
          controller: _area,
          errorText: _errors['area'],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.x4),
        AppTextField(
          key: const ValueKey('listing-duration'),
          label: 'Duration',
          hint: '4 hours',
          controller: _duration,
          errorText: _errors['duration'],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.x4),
        _ChoiceGroup(
          label: 'Difficulty',
          options: _difficultyChoices,
          selected: _difficulty,
          errorText: _errors['difficulty'],
          onSelected: (v) => setState(() => _difficulty = v),
        ),
        const SizedBox(height: AppSpacing.x4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                key: const ValueKey('listing-price'),
                label: 'Price per person (USD)',
                hint: '50',
                controller: _price,
                errorText: _errors['price'],
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: AppTextField(
                key: const ValueKey('listing-max-guests'),
                label: 'Max guests',
                hint: '10',
                controller: _maxGuests,
                errorText: _errors['maxGuests'],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x4),
        AppTextField(
          key: const ValueKey('listing-description'),
          label: 'Description',
          hint: 'What makes this experience special, and who it suits.',
          controller: _description,
          errorText: _errors['description'],
          maxLines: 5,
        ),
        const SizedBox(height: AppSpacing.x4),
        AppTextField(
          key: const ValueKey('listing-itinerary'),
          label: 'Itinerary (optional)',
          hint: '05:00 pick-up · 06:00 sunrise viewpoint · 09:00 breakfast',
          controller: _itinerary,
          errorText: _errors['itinerary'],
          maxLines: 4,
        ),
        const SizedBox(height: AppSpacing.x4),
        AppTextField(
          key: const ValueKey('listing-meeting-point'),
          label: 'Meeting point (optional)',
          hint: 'Lakeside clock tower',
          controller: _meetingPoint,
          errorText: _errors['meetingPoint'],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.x2),
        SwitchListTile(
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.accent,
          title: Text('Visible to travellers', style: AppTypography.label),
          subtitle: Text(
            'Paused listings stay here and keep their bookings, but are '
            'hidden from travellers.',
            style: AppTypography.caption,
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        AppButton(
          // "Save", not "publish": the listing is stored on the guide's own
          // workspace; traveler-facing publishing is a backend gap
          // (docs/api-gaps.md).
          label: _isEditing ? 'Save changes' : 'Save listing',
          loading: _saving,
          onPressed: _deleting ? null : _save,
        ),
        if (_isEditing) ...[
          const SizedBox(height: AppSpacing.x3),
          AppButton(
            label: 'Delete listing',
            variant: AppButtonVariant.outline,
            loading: _deleting,
            onPressed: _saving ? null : _confirmDelete,
          ),
        ],
      ],
    );
  }
}

/// A labeled row of single-select chips (category, difficulty).
class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.errorText,
  });

  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final String? errorText;

  static String _label(String value) => value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1)}';

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
            for (final option in options)
              AppFilterChip(
                label: _label(option),
                selected: option == selected,
                onTap: () => onSelected(option),
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
