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

/// Change the signed-in account's password (`POST /auth/change-password`).
///
/// The server requires the current password, then applies the same strength
/// policy it uses at registration; its 400 detail is surfaced verbatim so
/// "Current password is incorrect" is not rewritten into something vague.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text;
    final next = _next.text;

    if (current.isEmpty) {
      setState(() => _error = AppStrings.currentPasswordRequired);
      return;
    }
    if (next.length < 8) {
      setState(() => _error = AppStrings.passwordTooShort);
      return;
    }
    if (next != _confirm.text) {
      setState(() => _error = AppStrings.passwordMismatch);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: current,
            newPassword: next,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.passwordUpdated)),
      );
      context.pop();
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(AppStrings.changePassword, style: AppTypography.h3),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.changePasswordSubtitle,
                style:
                    AppTypography.body.copyWith(color: AppColors.textSecondary),
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
                label: AppStrings.currentPasswordLabel,
                controller: _current,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                prefixIcon: Icons.lock_outline,
              ),
              const SizedBox(height: AppSpacing.x4),
              AppTextField(
                label: AppStrings.newPasswordLabel,
                controller: _next,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                prefixIcon: Icons.lock_reset_outlined,
              ),
              const SizedBox(height: AppSpacing.x4),
              AppTextField(
                label: AppStrings.confirmPasswordLabel,
                controller: _confirm,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                prefixIcon: Icons.lock_reset_outlined,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.x6),
              AppButton(
                label: AppStrings.save,
                loading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
