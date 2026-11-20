import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/app_logo.dart';

/// First screen while the stored session is being validated. Branded, calm,
/// and never blocks indefinitely — session restore resolves to a route.
///
/// The white ground and the lockup are the same ones the OS splash screen
/// uses, so the hand-over from launch to Flutter is invisible: the artwork
/// does not jump, change size or flash against a different colour.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sized by width so the wordmark stays crisp and the mark keeps
              // its designed proportions on every phone.
              const AppLogoLockup(width: 232),
              const SizedBox(height: AppSpacing.x4),
              Text(
                AppStrings.tagline,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.x8),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
