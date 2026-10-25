import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../shared/widgets/app_button.dart';

/// `/faq` — the help page promised by the platform's public route table.
///
/// Copy is editorial, but every answer describes behaviour the app and
/// backend actually implement (city-scoped updates, guide verification,
/// booking requests, Maila Dai). Answers that would over-promise —
/// payments, cancellations, refunds — deliberately say what happens today
/// rather than a policy the platform does not yet enforce.
class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  int? _openIndex;

  static const _faqs = <(String, String)>[
    (
      'What is Guides Nepal?',
      'Guides Nepal connects travellers with independent local guides across '
          'Kathmandu, Pokhara, Lalitpur, Bhaktapur and Bharatpur. Every '
          'experience — heritage walks, food tours, treks, workshops — is led '
          'by a guide who lives there.',
    ),
    (
      'How do I book an experience?',
      'Open any experience from Explore or a city page and tap "Book now". '
          'Your request goes straight to the guide, and you can follow its '
          'status any time under the Trips tab.',
    ),
    (
      "What are the 'Local updates' on the home screen?",
      'Guides post live updates — a closed trail, extra spots on a sunrise '
          'hike, a moved meeting point. Home shows the feed for your chosen '
          'city, and you can switch cities from the same section.',
    ),
    (
      'How are guides verified?',
      'Guides join through an application and profile review. Verified '
          'guides show a badge on their profile alongside ratings and reviews '
          'from travellers who booked them.',
    ),
    (
      'Can I message a guide directly?',
      'Direct messaging is being built. Today the fastest way to reach a '
          'guide is through your booking request — guides reply with meeting '
          'details there. For trip planning, Maila Dai (the assistant on the '
          'Home screen) answers questions about destinations, food and culture.',
    ),
    (
      'What is Maila Dai?',
      'Maila Dai is the in-app travel assistant. Ask it about weather in '
          'Kathmandu, the best momo spots, trekking seasons or what to pack — '
          'it answers with local context.',
    ),
    (
      'How do I become a guide?',
      'Guides are onboarded by the Guides Nepal team: pick your expertise, '
          'cities and languages, set a default group size, then publish '
          'listings. Send us a note from the Contact page and we will start '
          'the process.',
    ),
    (
      'Which cities does Guides Nepal cover?',
      'Five cities today: Kathmandu, Pokhara, Lalitpur (Patan), Bhaktapur '
          'and Bharatpur — including Chitwan National Park excursions from '
          'Bharatpur.',
    ),
  ];

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
                Text('Help & FAQ', style: AppTypography.h1),
              ],
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'Answers to the questions travellers ask most. Anything else — '
              'write to us from the Contact page.',
              style: AppTypography.body
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.x5),
            for (var i = 0; i < _faqs.length; i++) ...[
              _FaqTile(
                question: _faqs[i].$1,
                answer: _faqs[i].$2,
                expanded: _openIndex == i,
                onTap: () => setState(() {
                  _openIndex = _openIndex == i ? null : i;
                }),
              ),
              const SizedBox(height: AppSpacing.x3),
            ],
            const SizedBox(height: AppSpacing.x3),
            AppButton(
              label: 'Contact us',
              expanded: true,
              onPressed: () => context.push('/contact'),
            ),
            const SizedBox(height: AppSpacing.x8),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.question,
    required this.answer,
    required this.expanded,
    required this.onTap,
  });

  final String question;
  final String answer;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.x4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(question, style: AppTypography.subtitle),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.secondary,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: AppSpacing.x3),
                Text(
                  answer,
                  style: AppTypography.body
                      .copyWith(color: AppColors.textSecondary, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
