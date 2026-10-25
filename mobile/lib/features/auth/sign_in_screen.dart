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

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signIn(
            email: _email.text.trim(),
            password: _password.text,
          );
      if (mounted) context.go('/home');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.terrain_rounded,
                      size: 56, color: AppColors.secondary),
                  const SizedBox(height: AppSpacing.x4),
                  Text(
                    'Welcome back',
                    style: AppTypography.h1,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    'Sign in to continue planning your Nepal trip.',
                    style: AppTypography.body
                        .copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.x8),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.x3),
                      decoration: BoxDecoration(
                        color: AppColors.errorSurface,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Text(
                        _error!,
                        style: AppTypography.small
                            .copyWith(color: AppColors.error),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x4),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: AppStrings.emailLabel,
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.isEmpty) return 'Email is required';
                      if (!value.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: AppStrings.passwordLabel,
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Password is required'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  AppButton(
                    label: AppStrings.signIn,
                    loading: _submitting,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  TextButton(
                    onPressed:
                        _submitting ? null : () => context.push('/sign-up'),
                    child: Text(
                      "Don't have an account? ${AppStrings.signUp}",
                      style: AppTypography.label
                          .copyWith(color: AppColors.secondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
