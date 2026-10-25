import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/widgets.dart';
import '../destinations/destination_data.dart';
import 'guide_models.dart';
import 'guide_repository.dart';

/// The signed-in guide's own profile (`GET|PUT /guide/onboarding`): display
/// name, expertise, the cities they guide in, languages, bio, experience and
/// the default group size.
///
/// A guide who never onboarded gets an empty form rather than an error. The
/// "profile complete" switch decides what is sent as `onboarding_completed`,
/// so a half-finished profile can be saved as a draft. Pops with `true` when
/// the server state changed, so the workspace can refresh its card.
class GuideProfileEditorScreen extends ConsumerStatefulWidget {
  const GuideProfileEditorScreen({super.key});

  @override
  ConsumerState<GuideProfileEditorScreen> createState() =>
      _GuideProfileEditorScreenState();
}

class _GuideProfileEditorScreenState
    extends ConsumerState<GuideProfileEditorScreen> {
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final _yearsExperience = TextEditingController();
  final _defaultMaxGuests = TextEditingController(text: '10');

  List<String> _expertise = [];
  List<String> _cities = [];
  List<String> _languages = [];
  bool _completed = false;

  bool _loading = false;
  String? _loadError;
  bool _saving = false;
  Map<String, String> _errors = const {};

  /// Chips offered for each list. Existing values the app does not offer are
  /// appended so editing never silently drops them.
  List<String> _expertiseChoices = GuideProfileDraft.expertiseOptions;
  List<String> _languageChoices = GuideProfileDraft.languageOptions;
  List<String> _cityChoices = _platformCities;

  static List<String> get _platformCities =>
      [for (final d in kDestinations) d.name];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _displayName,
      _bio,
      _yearsExperience,
      _defaultMaxGuests,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profile = await ref.read(guideRepositoryProvider).fetchOnboarding();
      if (!mounted) return;
      final draft = GuideProfileDraft.fromProfile(profile);
      _displayName.text = draft.displayName;
      _bio.text = draft.bio;
      _yearsExperience.text = draft.yearsExperience;
      _defaultMaxGuests.text = draft.defaultMaxGuestsText;
      setState(() {
        _expertise = List<String>.of(draft.expertiseAreas);
        _cities = List<String>.of(draft.cities);
        _languages = List<String>.of(draft.languages);
        _completed = draft.onboardingCompleted;
        _expertiseChoices = _withExtras(
          GuideProfileDraft.expertiseOptions,
          draft.expertiseAreas,
        );
        _languageChoices = _withExtras(
          GuideProfileDraft.languageOptions,
          draft.languages,
        );
        _cityChoices = _withExtras(_platformCities, draft.cities);
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

  /// `extras` first, then the curated options, without duplicates.
  static List<String> _withExtras(List<String> options, List<String> extras) {
    final extra = [
      for (final value in extras)
        if (value.trim().isNotEmpty && !options.contains(value)) value,
    ];
    return [...extra, ...options];
  }

  GuideProfileDraft _draft() => GuideProfileDraft(
        displayName: _displayName.text,
        expertiseAreas: _expertise,
        cities: _cities,
        languages: _languages,
        bio: _bio.text,
        yearsExperience: _yearsExperience.text,
        defaultMaxGuestsText: _defaultMaxGuests.text,
        onboardingCompleted: _completed,
      );

  void _toggle(List<String> selected, String value) {
    setState(() {
      if (selected.contains(value)) {
        selected.remove(value);
      } else {
        selected.add(value);
      }
    });
  }

  Future<void> _save() async {
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
      await ref
          .read(guideRepositoryProvider)
          .saveOnboarding(draft.toProfile());
      ref.invalidate(guideOnboardingProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Keep everything typed: the guide can fix the value and retry.
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
      'display_name': 'displayName',
      'bio': 'bio',
      'years_experience': 'yearsExperience',
      'default_max_guests': 'defaultMaxGuests',
      'expertise_areas': 'expertiseAreas',
      'cities': 'cities',
      'languages': 'languages',
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
        title: Text('Guide profile', style: AppTypography.h3),
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
          'These details are saved to your guide account, and you can change '
          'them any time.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.x4),
        AppTextField(
          key: const ValueKey('profile-display-name'),
          label: 'Display name',
          hint: 'Pemba Sherpa',
          controller: _displayName,
          errorText: _errors['displayName'],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.x4),
        _MultiChoiceGroup(
          label: 'What you guide',
          options: _expertiseChoices,
          selected: _expertise,
          errorText: _errors['expertiseAreas'],
          onToggle: (v) => _toggle(_expertise, v),
        ),
        const SizedBox(height: AppSpacing.x4),
        _MultiChoiceGroup(
          label: 'Cities you guide in',
          options: _cityChoices,
          selected: _cities,
          errorText: _errors['cities'],
          onToggle: (v) => _toggle(_cities, v),
        ),
        const SizedBox(height: AppSpacing.x4),
        _MultiChoiceGroup(
          label: 'Languages',
          options: _languageChoices,
          selected: _languages,
          errorText: _errors['languages'],
          onToggle: (v) => _toggle(_languages, v),
        ),
        const SizedBox(height: AppSpacing.x4),
        AppTextField(
          key: const ValueKey('profile-bio'),
          label: 'About you',
          hint: 'Fifteen seasons on the Annapurna trails, and I still know '
              'every tea house between here and Poon Hill.',
          controller: _bio,
          errorText: _errors['bio'],
          maxLines: 5,
        ),
        const SizedBox(height: AppSpacing.x4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                key: const ValueKey('profile-years'),
                label: 'Years guiding (optional)',
                hint: '15',
                controller: _yearsExperience,
                errorText: _errors['yearsExperience'],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: AppTextField(
                key: const ValueKey('profile-max-guests'),
                label: 'Default group size',
                hint: '10',
                controller: _defaultMaxGuests,
                errorText: _errors['defaultMaxGuests'],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x2),
        SwitchListTile(
          key: const ValueKey('profile-complete'),
          value: _completed,
          onChanged: (v) => setState(() => _completed = v),
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.accent,
          title: Text('Profile complete', style: AppTypography.label),
          subtitle: Text(
            'Turn this on once your name, expertise, cities, languages and '
            'bio are filled in. Until then the profile saves as a draft.',
            style: AppTypography.caption,
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        AppButton(
          label: _completed ? 'Save profile' : 'Save draft',
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// A labeled row of multi-select chips (expertise, cities, languages).
class _MultiChoiceGroup extends StatelessWidget {
  const _MultiChoiceGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.errorText,
  });

  final String label;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;
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
                selected: selected.contains(option),
                onTap: () => onToggle(option),
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
