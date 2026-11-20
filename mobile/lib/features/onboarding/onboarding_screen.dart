import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../l10n/app_strings.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_logo.dart';

/// Intro screen shown before sign-in. Gives a first-time traveler the
/// product promise and a clear path to the two account actions.
///
/// The three slides are a pager, so the pager has to say so: without dots a
/// traveler sees one promise and never learns there are two more, and a swipe
/// that happens by accident is the only way to discover them.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const slides = <_OnboardingSlide>[
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
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const slides = OnboardingScreen.slides;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            children: [
              Row(
                children: [
                  // First screen a traveler sees: the brand, then the choices.
                  const AppLogoLockup(width: 108),
                  const Spacer(),
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
                  controller: _controller,
                  onPageChanged: (index) => setState(() => _index = index),
                  children: [
                    for (final slide in slides)
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
                                style: AppTypography.body
                                    .copyWith(color: AppColors.textSecondary),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _PageDots(
                count: slides.length,
                index: _index,
                onSelected: (index) => _controller.animateToPage(
                  index,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                ),
              ),
              const SizedBox(height: AppSpacing.x5),
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

/// Position indicator for the pager. Tapping a dot moves the pager, and each
/// dot carries a 44 dp hit target even though the mark itself is 6 dp.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.index,
    required this.onSelected,
  });

  final int count;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Page ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Semantics(
              button: true,
              selected: i == index,
              label: 'Page ${i + 1}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(i),
                child: SizedBox(
                  height: AppSpacing.minTouchTarget,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
                      width: i == index ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            i == index ? AppColors.secondary : AppColors.border,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusPill),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
