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

/// Create (`POST /host/experiences`) or edit
/// (`PATCH /host/experiences/{id}`) one of the host's experiences.
///
/// The patch endpoint replaces every field, so this form always submits the
/// whole record. An id that is not in the host's own list renders the
/// "no longer available" state instead of an empty create form.
class HostExperienceEditorScreen extends ConsumerStatefulWidget {
  const HostExperienceEditorScreen({super.key, this.experienceId});

  /// Null when creating.
  final int? experienceId;

  @override
  ConsumerState<HostExperienceEditorScreen> createState() =>
      _HostExperienceEditorScreenState();
}

class _HostExperienceEditorScreenState
    extends ConsumerState<HostExperienceEditorScreen> {
  final _title = TextEditingController();
  final _city = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _duration = TextEditingController();
  final _heroImage = TextEditingController();

  bool _loading = false;
  bool _missing = false;
  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  bool get _isEdit => widget.experienceId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _city.dispose();
    _category.dispose();
    _description.dispose();
    _price.dispose();
    _duration.dispose();
    _heroImage.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(hostRepositoryProvider).fetchExperiences();
      final match = list.where((e) => e.id == widget.experienceId).toList();
      if (match.isEmpty) {
        if (mounted) setState(() => _missing = true);
        return;
      }
      final draft = HostExperienceDraft.fromExperience(match.first);
      _title.text = draft.title;
      _city.text = draft.city;
      _category.text = draft.category;
      _description.text = draft.description;
      _price.text = draft.price;
      _duration.text = draft.duration;
      _heroImage.text = draft.heroImage;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final draft = HostExperienceDraft(
      title: _title.text,
      city: _city.text,
      category: _category.text,
      description: _description.text,
      price: _price.text,
      duration: _duration.text,
      heroImage: _heroImage.text,
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
        await repo.updateExperience(widget.experienceId!, draft);
      } else {
        await repo.createExperience(draft);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.hostExperienceSaved)),
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
          _isEdit ? AppStrings.hostEditExperience : AppStrings.hostCreateExperience,
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
            label: AppStrings.hostCategoryLabel,
            controller: _category,
            errorText: _fieldErrors['category'],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            label: AppStrings.hostDescriptionLabel,
            controller: _description,
            errorText: _fieldErrors['description'],
            maxLines: 5,
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
            label: AppStrings.hostPriceLabel,
            controller: _price,
            errorText: _fieldErrors['price'],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.x4),
          AppTextField(
            label: AppStrings.hostHeroImageLabel,
            controller: _heroImage,
            keyboardType: TextInputType.url,
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
