import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/widgets.dart';
import '../auth/auth_repository.dart';
import 'profile_draft.dart';

/// Edits the signed-in traveler's name, photo and contact details.
///
/// The server stores these through `PATCH /profile/me` and
/// `POST /profile/photos/upload`; nothing here can change email, password or
/// role, because nothing here is allowed to. Saving puts the server's
/// refreshed identity straight into the session, so the Profile tab updates
/// without a second fetch.
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  /// The server's upload cap (`backend/app/core/storage.py`).
  static const int _maxPhotoBytes = 5 * 1024 * 1024;

  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _bio;

  List<int>? _pickedBytes;
  String? _pickedName;
  String? _pickedType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    final draft =
        user == null ? const ProfileDraft() : ProfileDraft.fromUser(user);
    _firstName = TextEditingController(text: draft.firstName);
    _lastName = TextEditingController(text: draft.lastName);
    _phone = TextEditingController(text: draft.phone);
    _bio = TextEditingController(text: draft.bio);
    // Live validation: a message that only refreshes on some other rebuild
    // tells the traveler about a problem that may already be fixed.
    for (final controller in [_firstName, _lastName, _phone, _bio]) {
      controller.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _bio.dispose();
    super.dispose();
  }

  ProfileDraft get _draft => ProfileDraft(
        firstName: _firstName.text,
        lastName: _lastName.text,
        phone: _phone.text,
        bio: _bio.text,
      );

  Future<void> _pickPhoto() async {
    if (_saving) return;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        // A portrait is shown at 58 dp; 1200 px is generous and keeps uploads
        // well inside the server's 5 MB ceiling on a phone camera.
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxPhotoBytes) {
        setState(() => _error = AppStrings.photoTooLarge);
        return;
      }
      setState(() {
        _pickedBytes = bytes;
        _pickedName = file.name.isEmpty ? 'avatar.jpg' : file.name;
        _pickedType = _detectType(file.mimeType, _pickedName!);
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open your photos.');
      }
    }
  }

  /// The server accepts JPEG, PNG and WebP and checks the bytes, so the type
  /// travels with the upload rather than being guessed from the extension.
  String _detectType(String? mime, String name) {
    if (mime != null && mime.startsWith('image/')) return mime;
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _save() async {
    if (_saving) return;
    final draft = _draft;
    final errors = draft.validate();
    if (errors.isNotEmpty) {
      // Surface through the form so the offending field carries its message.
      _formKey.currentState?.validate();
      setState(() => _error = null);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final controller = ref.read(authControllerProvider.notifier);
    var photoFailed = false;
    try {
      final payload = draft.toJson();
      await controller.updateProfile(
        firstName: payload['firstName'] as String,
        lastName: payload['lastName'] as String,
        phone: payload['phone'] as String,
        bio: payload['bio'] as String,
      );

      final bytes = _pickedBytes;
      if (bytes != null) {
        try {
          final url = await controller.uploadAvatar(
            bytes: bytes,
            filename: _pickedName ?? 'avatar.jpg',
            contentType: _pickedType ?? 'image/jpeg',
          );
          // Second PATCH: the photo only becomes visible once its path is
          // stored on the user row.
          await controller.updateProfile(avatarUrl: url);
        } on ApiException {
          photoFailed = true;
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          photoFailed
              ? 'Profile saved, but the photo could not be uploaded.'
              : AppStrings.profileSaved,
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final avatarUrl = user?.avatarUrl;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: AppStrings.back,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
        ),
        title: Text(AppStrings.editProfile, style: AppTypography.h3),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.x2,
            AppSpacing.gutter,
            AppSpacing.x10,
          ),
          children: [
            Center(
              child: Column(
                children: [
                  _AvatarPreview(
                    initials: user?.initials ?? '?',
                    remoteUrl: avatarUrl,
                    pickedBytes: _pickedBytes,
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  TextButton(
                    onPressed: _saving ? null : _pickPhoto,
                    child: Text(
                      AppStrings.changePhoto,
                      style: AppTypography.label
                          .copyWith(color: AppColors.secondary),
                    ),
                  ),
                  // The address identifies the account and is not editable
                  // here; saying so costs one line and prevents the traveler
                  // hunting for a field that does not exist.
                  Text(
                    user?.email ?? '',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x4),
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
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    label: AppStrings.firstNameLabel,
                    controller: _firstName,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.givenName],
                    errorText: _draft.validate()['firstName'],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  AppTextField(
                    label: AppStrings.lastNameLabel,
                    controller: _lastName,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.familyName],
                    errorText: _draft.validate()['lastName'],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  AppTextField(
                    label: AppStrings.phoneLabel,
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    errorText: _draft.validate()['phone'],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  AppTextField(
                    label: AppStrings.bioLabel,
                    hint: AppStrings.bioHelper,
                    controller: _bio,
                    maxLines: 4,
                    errorText: _draft.validate()['bio'],
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      Formatters.fieldCounter(
                        _bio.text.characters.length,
                        ProfileDraft.bioMaxLength,
                      ),
                      style: AppTypography.caption.copyWith(
                        color: _bio.text.characters.length >
                                ProfileDraft.bioMaxLength
                            ? AppColors.error
                            : AppColors.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  AppButton(
                    label: AppStrings.save,
                    loading: _saving,
                    onPressed: _save,
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).maybePop(),
                    child: Text(
                      AppStrings.cancel,
                      style: AppTypography.label
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular preview: a freshly picked photo wins over the stored one, which
/// wins over the initials.
class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.initials,
    required this.remoteUrl,
    required this.pickedBytes,
  });

  final String initials;
  final String? remoteUrl;
  final List<int>? pickedBytes;

  @override
  Widget build(BuildContext context) {
    final bytes = pickedBytes;
    final stored = remoteUrl;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.peach, AppColors.surfacePeach],
        ),
      ),
      child: CircleAvatar(
        radius: 40,
        backgroundColor: AppColors.surface,
        foregroundImage: bytes != null
            ? MemoryImage(Uint8List.fromList(bytes))
            : (stored != null && stored.isNotEmpty)
                ? NetworkImage(AppConfig.resolveMedia(stored))
                : null,
        child: Text(
          initials,
          style: AppTypography.h2.copyWith(color: AppColors.secondary),
        ),
      ),
    );
  }
}
