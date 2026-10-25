import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/app_button.dart';

/// Intro screen shown before sign-in. Gives a first-time traveler the
/// product promise and a clear path to the two account actions.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      icon: Icons.explore_outlined,
      title: 'Find your Nepal.',
      body: 'Discover remarkable places and unforgettable experiences with '
          'the people who know them best.',
    ),
    _OnboardingSlide(
      icon: Icons.groups_outlined,
      title: 'Meet local guides.',
      body: 'Connect with knowledgeable local guides who open doors to '
          'culture, food and adventure across five cities.',
    ),
    _OnboardingSlide(
      icon: Icons.card_travel_outlined,
      title: 'Book with confidence.',
      body: 'Request a date, follow your booking status and keep every trip '
          'in one place.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Public help pages are reachable before sign-in too.
                  TextButton(
                    onPressed: () => context.push('/faq'),
                    child: const Text('Help'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/sign-in'),
                    child: const Text(AppStrings.close),
                  ),
                ],
              ),
              Expanded(
                child: PageView(
                  children: [
                    for (final slide in _slides)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 104,
                              height: 104,
                              decoration: const BoxDecoration(
                                color: AppColors.surfacePeach,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(slide.icon,
                                  size: 48, color: AppColors.secondary),
                            ),
                            const SizedBox(height: AppSpacing.x6),
                            Text(
                              slide.title,
                              style: AppTypography.displayMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.x4),
                              child: Text(
                                slide.body,
                                style: AppTypography.body.copyWith(
                                    color: AppColors.textSecondary),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              AppButton(
                label: AppStrings.signUp,
                onPressed: () => context.go('/sign-up'),
              ),
              const SizedBox(height: AppSpacing.x2),
              AppButton(
                label: AppStrings.signIn,
                variant: AppButtonVariant.ghost,
                onPressed: () => context.go('/sign-in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}
