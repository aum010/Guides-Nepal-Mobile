import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../l10n/app_strings.dart';

/// First screen while the stored session is being validated. Branded, calm,
/// and never blocks indefinitely — session restore resolves to a route.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.terrain_rounded,
                    size: 44, color: AppColors.accent),
              ),
              const SizedBox(height: AppSpacing.x5),
              Text(
                AppStrings.appName,
                style: AppTypography.h1.copyWith(
                  color: AppColors.textOnPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                AppStrings.tagline,
                style: AppTypography.body.copyWith(
                  color: AppColors.textOnPrimary.withValues(alpha: 0.78),
                ),
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
