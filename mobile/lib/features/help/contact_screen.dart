import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_button.dart';
import '../auth/auth_repository.dart';

/// `/contact` — the contact page promised by the platform's route table.
///
/// Submissions go to the public `POST /inquiries` endpoint, which stores the
/// message as a support ticket so the support team triages it from their
/// console. Nothing here requires auth: a traveller with a booking problem
/// must be able to reach a human before they can sign in again.
class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key});

  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  String _category = 'general';
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  static const _categories = <(String, String)>[
    ('general', 'General question'),
    ('booking', 'Booking help'),
    ('guide', 'Become a guide'),
    ('host', 'Become a host'),
    ('technical', 'Technical issue'),
  ];

  @override
  void initState() {
    super.initState();
    // Prefill from the signed-in account when there is one — one less thing
    // to retype while already frustrated.
    final user = ref.read(authControllerProvider).user;
    if (user != null) {
      _nameController.text = user.displayName;
      _emailController.text = user.email;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).post('/inquiries', data: {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'subject': _subjectController.text.trim(),
        'message': _messageController.text.trim(),
        'category': _category,
      });
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitted = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          children: [
            Row(
              children: [
                const BackButton(),
                const SizedBox(width: AppSpacing.x2),
                Text('Contact us', style: AppTypography.h1),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'A question about a booking, an idea for a city we do not cover, '
              'or want to become a guide? We read every message.',
              style:
                  AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.x5),
            if (_submitted) ...[
              _successView(),
            ] else
              _contactForm(),
            const SizedBox(height: AppSpacing.x8),
          ],
        ),
      ),
    );
  }

  Widget _successView() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mark_email_read_rounded,
              size: 36, color: AppColors.secondary),
          const SizedBox(height: AppSpacing.x4),
          Text('Message sent', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.x2),
          Text(
            'Thanks — our support team has your message and will reply to '
            '${_emailController.text.trim()}. Typical reply time is one '
            'business day.',
            style:
                AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.x5),
          AppButton(
            label: 'Send another message',
            variant: AppButtonVariant.outline,
            expanded: true,
            onPressed: () => setState(() {
              _submitted = false;
              _subjectController.clear();
              _messageController.clear();
            }),
          ),
        ],
      ),
    );
  }

  Widget _contactForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('Topic'),
          const SizedBox(height: AppSpacing.x2),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: _inputDecoration(),
            items: [
              for (final (value, label) in _categories)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: (v) => setState(() => _category = v ?? 'general'),
          ),
          const SizedBox(height: AppSpacing.x4),
          _fieldLabel('Your name'),
          const SizedBox(height: AppSpacing.x2),
          TextFormField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(hint: 'Full name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
          ),
          const SizedBox(height: AppSpacing.x4),
          _fieldLabel('Email'),
          const SizedBox(height: AppSpacing.x2),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(hint: 'you@example.com'),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return 'Please enter your email';
              if (!value.contains('@')) return 'Enter a valid email address';
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.x4),
          _fieldLabel('Subject'),
          const SizedBox(height: AppSpacing.x2),
          TextFormField(
            controller: _subjectController,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(hint: 'What is this about?'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Please add a subject' : null,
          ),
          const SizedBox(height: AppSpacing.x4),
          _fieldLabel('Message'),
          const SizedBox(height: AppSpacing.x2),
          TextFormField(
            controller: _messageController,
            maxLines: 5,
            maxLength: 2000,
            decoration: _inputDecoration(hint: 'Tell us how we can help…'),
            validator: (v) => (v == null || v.trim().length < 10)
                ? 'Please write at least 10 characters'
                : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.x3),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 18, color: AppColors.favoriteActive),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(_error!,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.favoriteActive)),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.x5),
          AppButton(
            label: _submitting ? 'Sending…' : 'Send message',
            expanded: true,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(text, style: AppTypography.label);

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          vertical: AppSpacing.x3,
          horizontal: AppSpacing.x4,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.secondary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.favoriteActive),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.favoriteActive, width: 1.6),
        ),
      );
}
