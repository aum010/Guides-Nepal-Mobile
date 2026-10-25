import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Destination presentation metadata for the five cities verified in the
/// platform content model (`frontend/src/data/kathmanduRichData.ts` and the
/// site's city pages).
///
/// This is display data only — names, icons and short editorial taglines.
/// Anything shown on a destination screen that comes from the server
/// (experiences, guides) is fetched live; nothing here fabricates ratings,
/// reviews or availability.
class Destination {
  const Destination({
    required this.name,
    required this.slug,
    required this.tagline,
    required this.description,
    required this.icon,
    required this.highlights,
    required this.gradient,
  });

  final String name;
  final String slug;
  final String tagline;
  final String description;
  final IconData icon;
  final List<String> highlights;
  final LinearGradient gradient;
}

const kDestinations = <Destination>[
  Destination(
    name: 'Kathmandu',
    slug: 'Kathmandu',
    tagline: 'Valley of living temples',
    description:
        'The capital valley packs centuries of Newari craft, courtyard '
        'temples and buzzing bazaars into a handful of square kilometres. '
        'Walk Durbar Square at dawn, then trace the backstreets of Patan '
        'and Bhaktapur.',
    icon: Icons.account_balance_outlined,
    highlights: [
      'Durbar Square heritage walks',
      'Newari food tours',
      'Swayambhunath at sunrise',
      'Patan craft workshops',
    ],
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.tileKathmanduStart, AppColors.tileKathmanduEnd],
    ),
  ),
  Destination(
    name: 'Pokhara',
    slug: 'Pokhara',
    tagline: 'Lakeside under the Himalaya',
    description:
        'Phewa Tal mirrors the Annapurna skyline, and the lakeside strip '
        'makes an easy base for paragliding, sunrise viewpoints and short '
        'hills walks.',
    icon: Icons.water_outlined,
    highlights: [
      'Phewa Tal boating',
      'Sarangkot sunrise',
      'Paragliding over the valley',
      'World Peace Pagoda walk',
    ],
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.tilePokharaStart, AppColors.tilePokharaEnd],
    ),
  ),
  Destination(
    name: 'Lalitpur',
    slug: 'Lalitpur',
    tagline: 'City of fine craft',
    description:
        'Also called Patan, this city is famed for its bronze casters, '
        'wood carvers and the serene Krishna Mandir at the heart of a '
        'masterfully laid-out Durbar Square.',
    icon: Icons.palette_outlined,
    highlights: [
      'Patan Durbar Square',
      'Metalwork and casting studios',
      'Golden Temple courtyard',
      'Newari cooking classes',
    ],
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.tileLalitpurStart, AppColors.tileLalitpurEnd],
    ),
  ),
  Destination(
    name: 'Bhaktapur',
    slug: 'Bhaktapur',
    tagline: 'Medieval town, still living',
    description:
        'The best-preserved medieval town in the valley: brick lanes, '
        'pottery squares and the magnificent 55-Window Palace, with almost '
        'no traffic in the old core.',
    icon: Icons.foundation_outlined,
    highlights: [
      '55-Window Palace',
      'Pottery Square',
      'Juju Dhau (king curd) tasting',
      'Traditional pottery classes',
    ],
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.tileBhaktapurStart, AppColors.tileBhaktapurEnd],
    ),
  ),
  Destination(
    name: 'Bharatpur',
    slug: 'Bharatpur',
    tagline: 'Gateway to the Chitwan lowlands',
    description:
        'The gateway city to Chitwan National Park, where the hills give '
        'way to subtropical terai and some of Nepal’s best wildlife '
        'experiences.',
    icon: Icons.pets_outlined,
    highlights: [
      'Chitwan National Park safari',
      'Tharu cultural evenings',
      'Canoeing the Rapti',
      'Birdwatching in the terai',
    ],
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.tileBharatpurStart, AppColors.tileBharatpurEnd],
    ),
  ),
];

Destination destinationForSlug(String slug) => kDestinations.firstWhere(
      (d) => d.slug.toLowerCase() == slug.toLowerCase(),
      orElse: () => kDestinations.first,
    );
