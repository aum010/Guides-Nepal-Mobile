import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../models/booking.dart';

/// The single booking-status vocabulary.
///
/// A traveler's Trips list and a guide's request list show the same states, so
/// they must not each own a copy of the mapping — two palettes is exactly how
/// a cancelled booking ends up red on one screen and green on another. Colour
/// is never the only signal: the label carries the state in words.
class BookingStatusChip extends StatelessWidget {
  const BookingStatusChip({super.key, required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = bookingStatusColors(status);
    final label = status.name.toUpperCase();

    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2 + 2,
          vertical: AppSpacing.x1,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child:
            Text(label, style: AppTypography.micro.copyWith(color: foreground)),
      ),
    );
  }
}

/// Status → (surface, ink). Tinted surfaces keep the chip quiet against the
/// cream canvas while the ink stays above 4.5:1.
(Color, Color) bookingStatusColors(BookingStatus status) => switch (status) {
      BookingStatus.upcoming || BookingStatus.accepted => (
          AppColors.successSurface,
          AppColors.success,
        ),
      BookingStatus.completed => (
          AppColors.surfacePeach,
          AppColors.secondary,
        ),
      BookingStatus.cancelled || BookingStatus.rejected => (
          AppColors.errorSurface,
          AppColors.error
        ),
      BookingStatus.archived => (AppColors.border, AppColors.textSecondary),
    };
