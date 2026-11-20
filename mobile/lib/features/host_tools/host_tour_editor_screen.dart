import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/widgets.dart';
import 'host_models.dart';
import 'host_repository.dart';

/// Create (`POST /host/tours`) or edit (`PATCH /host/tours/{id}`) a host tour.
///
/// A tour carries the route and the practical details a traveller needs
/// (itinerary, meeting point, difficulty, group size), so the form mirrors the
/// server's `HostTourCreate` constraints exactly rather than asking for a
/// partial update.
class HostTourEditorScreen extends ConsumerStatefulWidget {
  const HostTourEditorScreen({super.key, this.tourId});

  /// Null when creating.
  final int? tourId;

  @override
  ConsumerState<HostTourEditorScreen> createState() =>
      _HostTourEditorScreenState();
}

class _HostTourEditorScreenState extends ConsumerState<HostTourEditorScreen> {
  final _title = TextEditingController();
  final _city = TextEditingController();
  final _description = TextEditingController();
  final _itinerary = TextEditingController();
  final _meetingPoint = TextEditingController();
  final _duration = TextEditingController();
  final _difficulty = TextEditingController();
  final _maxGuests = TextEditingController();
  final _price = TextEditingController();

  bool _loading = false;
  bool _missing = false;
  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  bool get _isEdit => widget.tourId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _city.dispose();
    _description.dispose();
    _itinerary.dispose();
    _meetingPoint.dispose();
    _duration.dispose();
    _difficulty.dispose();
    _maxGuests.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(hostRepositoryProvider).fetchTours();
      final match = list.where((t) => t.id == widget.tourId).toList();
      if (match.isEmpty) {
        if (mounted) setState(() => _missing = true);
        return;
      }
      final draft = HostTourDraft.fromTour(match.first);
      _title.text = draft.title;
      _city.text = draft.city;
      _description.text = draft.description;
      _itinerary.text = draft.itinerary;
      _meetingPoint.text = draft.meetingPoint;
      _duration.text = draft.duration;
      _difficulty.text = draft.difficulty;
      _maxGuests.text = draft.maxGuests;
      _price.text = draft.price;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final draft = HostTourDraft(
      title: _title.text,
      city: _city.text,
      description: _description.text,
      itinerary: _itinerary.text,
      meetingPoint: _meetingPoint.text,
      duration: _duration.text,
      difficulty: _difficulty.text,
      maxGuests: _maxGuests.text,
      price: _price.text,
    );
    final errors = draft.validate();
    setState(() {
      _fieldErrors = errors;
      _error = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _submitting = true);
    try {
      final repo = ref.read(hostRepositoryProvider);
      if (_isEdit) {
        await repo.updateTour(widget.tourId!, draft);
      } else {
        await repo.createTour(draft);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.hostTourSaved)),
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          _isEdit ? AppStrings.hostEditTour : AppStrings.hostCreateTour,
          style: AppTypography.h3,
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_missing) {
      return const EmptyStateView(
        icon: Icons.search_off_rounded,
        title: AppStrings.hostRecordMissingTitle,
        message: AppStrings.hostRecordMissingBody,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.x3),
              decoration: BoxDecoration(
                color: AppColors.errorSurface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                _error!,
                style: AppTypography.small.copyWith(color: AppColors.error),
              ),
            ),
            const SizedBox(height: AppSpacing.x4),
          ],
          AppTextField(
            label: AppStrings.hostTitleLabel,
            controller: _title,
            errorText: _fieldErrors['title'],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            label: AppStrings.hostCityLabel,
            controller: _city,
            errorText: _fieldErrors['city'],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            label: AppStrings.hostDescriptionLabel,
            controller: _description,
            errorText: _fieldErrors['description'],
            maxLines: 4,
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            label: AppStrings.hostItineraryLabel,
            controller: _itinerary,
            errorText: _fieldErrors['itinerary'],
            maxLines: 4,
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            label: AppStrings.hostMeetingPointLabel,
            controller: _meetingPoint,
            errorText: _fieldErrors['meetingPoint'],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            label: AppStrings.hostDurationLabel,
            controller: _duration,
            errorText: _fieldErrors['duration'],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            label: AppStrings.hostDifficultyLabel,
            controller: _difficulty,
            errorText: _fieldErrors['difficulty'],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            label: AppStrings.hostMaxGuestsLabel,
            controller: _maxGuests,
            errorText: _fieldErrors['maxGuests'],
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            label: AppStrings.hostPriceLabel,
            controller: _price,
            errorText: _fieldErrors['price'],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: AppSpacing.x6),
          AppButton(
            label: AppStrings.save,
            loading: _submitting,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
