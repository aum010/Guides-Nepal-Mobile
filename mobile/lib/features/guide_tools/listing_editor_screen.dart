import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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

  /// The photo already stored on the server, and one the guide just picked.
  /// The picked bytes are uploaded after the listing itself is saved, because
  /// the upload route is keyed by listing id.
  String? _photoUrl;
  Uint8List? _pickedBytes;
  String _pickedName = 'photo.jpg';
  String _pickedType = 'image/jpeg';
  bool _photoBusy = false;

  static const _maxPhotoBytes = 5 * 1024 * 1024;
  final _picker = ImagePicker();

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
        _photoUrl = listing.heroImage;
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

  /// Opens the photo library and holds the choice until save.
  Future<void> _pickPhoto() async {
    if (_photoBusy || _saving) return;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        // Downscale on the device: cards never need more than this, and it
        // keeps most photos under the server's 5 MB cap.
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxPhotoBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a photo smaller than 5 MB.')),
        );
        return;
      }
      setState(() {
        _pickedBytes = bytes;
        _pickedName = file.name.isEmpty ? 'photo.jpg' : file.name;
        _pickedType = _detectType(file.mimeType, _pickedName);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open your photos.')),
        );
      }
    }
  }

  /// Clears the photo. On an existing listing this is saved immediately, so
  /// the answer to "is my photo gone?" is not deferred behind another save.
  Future<void> _removePhoto() async {
    if (_photoBusy || _saving) return;
    setState(() {
      _pickedBytes = null;
      _photoBusy = _isEditing && _photoUrl != null;
    });
    if (!_isEditing || _photoUrl == null) {
      setState(() => _photoUrl = null);
      return;
    }
    try {
      await ref.read(guideRepositoryProvider).removeListingPhoto(widget.listingId!);
      if (mounted) setState(() => _photoUrl = null);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  /// Picks a content type the server accepts. The picked file's own MIME type
  /// is trusted first (it is accurate on web), then the extension.
  static String _detectType(String? mimeType, String name) {
    const allowed = {'image/jpeg', 'image/png', 'image/webp'};
    if (mimeType != null && allowed.contains(mimeType)) return mimeType;
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

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

    final bool photoFailed;
    try {
      final repo = ref.read(guideRepositoryProvider);
      late final int listingId;
      if (_isEditing) {
        await repo.updateListing(widget.listingId!, draft);
        listingId = widget.listingId!;
      } else {
        listingId = (await repo.createListing(draft)).id;
      }

      // The photo is a second request, keyed by the listing id. A failure here
      // must not make the saved listing look unsaved — and must not create a
      // duplicate on retry — so it is reported separately.
      var failed = false;
      final bytes = _pickedBytes;
      if (bytes != null) {
        try {
          await repo.uploadListingPhoto(
            listingId,
            bytes: bytes,
            filename: _pickedName,
            contentType: _pickedType,
          );
        } on ApiException {
          failed = true;
        }
      }
      photoFailed = failed;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = _serverFieldErrors(e);
        _saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (photoFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listing saved, but the photo could not be uploaded.'),
        ),
      );
    }
    Navigator.of(context).pop(true);
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
        _PhotoField(
          photoUrl: _photoUrl,
          pickedBytes: _pickedBytes,
          busy: _photoBusy || _saving,
          onPick: _pickPhoto,
          onRemove: _removePhoto,
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
          // Saving is publishing: an active listing is bookable in the public
          // catalogue immediately (docs/api-gaps.md).
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

/// The listing's cover photo: what exists, what was just picked, and the
/// controls to change or remove it.
class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.photoUrl,
    required this.pickedBytes,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final String? photoUrl;
  final Uint8List? pickedBytes;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        pickedBytes != null || (photoUrl != null && photoUrl!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cover photo', style: AppTypography.label),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: SizedBox(
                width: 104,
                height: 78,
                child: pickedBytes != null
                    ? Image.memory(pickedBytes!, fit: BoxFit.cover)
                    : NetworkImageView(
                        url: photoUrl,
                        semanticsLabel: 'Listing cover photo',
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPhoto
                        ? 'Travellers see this photo on your card and detail page.'
                        : 'Add a photo so travellers can see what they are booking.',
                    style: AppTypography.caption,
                  ),
                  Wrap(
                    spacing: AppSpacing.x2,
                    children: [
                      TextButton.icon(
                        onPressed: busy ? null : onPick,
                        icon: Icon(
                          hasPhoto
                              ? Icons.photo_library_outlined
                              : Icons.add_photo_alternate_outlined,
                          size: 18,
                        ),
                        label: Text(hasPhoto ? 'Change photo' : 'Add photo'),
                      ),
                      if (hasPhoto)
                        TextButton(
                          onPressed: busy ? null : onRemove,
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
