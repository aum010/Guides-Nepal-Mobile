import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/widgets.dart';
import 'auth_repository.dart';

/// Password reset request (`POST /auth/forgot-password`).
///
/// The backend owns the reset itself: it emails a link through its configured
/// mail service and returns one generic message whether or not the address is
/// registered. This screen therefore never says "no such account" and never
/// claims delivery on its own — it shows what the server answered, and points
/// at support because a deployment without mail configured cannot deliver.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _submitting = false;
  String? _fieldError;
  String? _error;
  String? _serverMessage;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return AppStrings.emailRequired;
    if (!email.contains('@')) return AppStrings.emailInvalid;
    return null;
  }

  Future<void> _submit() async {
    final error = _validate(_email.text);
    setState(() => _fieldError = error);
    if (error != null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final message = await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _serverMessage = message);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = AppStrings.genericError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _serverMessage != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(AppStrings.forgotPasswordTitle, style: AppTypography.h3),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: sent ? _confirmation(context) : _form(context),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.forgotPasswordBody,
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.x6),
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
          label: AppStrings.emailLabel,
          controller: _email,
          hint: 'you@example.com',
          errorText: _fieldError,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          prefixIcon: Icons.mail_outline,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: AppSpacing.x6),
        AppButton(
          label: AppStrings.sendResetLink,
          loading: _submitting,
          onPressed: _submit,
        ),
        const SizedBox(height: AppSpacing.x2),
        TextButton(
          onPressed: _submitting ? null : () => context.pop(),
          child: Text(
            AppStrings.backToSignIn,
            style: AppTypography.label.copyWith(color: AppColors.secondary),
          ),
        ),
      ],
    );
  }

  Widget _confirmation(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined,
            size: 48, color: AppColors.success),
        const SizedBox(height: AppSpacing.x4),
        Text(
          AppStrings.resetLinkSentTitle,
          style: AppTypography.h2,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.x2),
        // The server's own wording: it is deliberately the same for a
        // registered and an unknown address.
        Text(
          _serverMessage!,
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.x4),
        Text(
          AppStrings.resetDeliveryNote,
          style: AppTypography.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.x6),
        AppButton(
          label: AppStrings.backToSignIn,
          onPressed: () => context.pop(),
        ),
        const SizedBox(height: AppSpacing.x2),
        AppButton(
          label: AppStrings.contactSupport,
          variant: AppButtonVariant.outline,
          onPressed: () => context.push('/contact'),
        ),
      ],
    );
  }
}
