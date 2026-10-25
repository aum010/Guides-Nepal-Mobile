import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// One tab in the [FloatingNavBar].
class FloatingNavItem {
  const FloatingNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating pill navigation — the primary tab switcher.
///
/// The active tab lives in a raised circular badge that overlaps the bar's
/// top edge; the bar's outline dips into a concentric notch around it so
/// the badge reads as *seated in* the bar rather than floating over it.
/// Switching tabs blends three motions: the badge and notch glide to the
/// new slot together (so the notch never lags the icon), the badge pops
/// in scale as it lands, and the label fades its colour and weight.
///
/// Geometry is deliberate: layout height is identical to the old flat pill,
/// so screens above need no extra bottom padding — only the badge paints
/// above the bar's box (the Stack does not clip).
class FloatingNavBar extends StatefulWidget {
  const FloatingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<FloatingNavItem> items;

  @override
  State<FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<FloatingNavBar> {
  /// Bar height — unchanged from the flat-pill version.
  static const double _barHeight = 68;

  /// Badge diameter and its centre relative to the bar's top edge
  /// (negative = above it): roughly two thirds of the badge rises over
  /// the content, the rest nests into the notch.
  static const double _badgeRadius = 24;
  static const double _badgeCenterY = -8;

  /// Clear space between the badge and the notch's lip, so a thin ring of
  /// background always outlines the badge against the bar.
  static const double _notchGap = 5;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x4, AppSpacing.x1, AppSpacing.x4, AppSpacing.x1 + 2,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Slot centres: the same split the Row below uses, so the badge
            // lands exactly on top of its item's column.
            final slotWidth = constraints.maxWidth / items.length;
            final targetX = slotWidth * (widget.selectedIndex + 0.5);

            return SizedBox(
              height: _barHeight,
              child: TweenAnimationBuilder<double>(
                // No begin: the first build lands on the selected slot with
                // no motion; later index changes glide from the live value.
                tween: Tween<double>(end: targetX),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeInOutCubic,
                builder: (context, badgeX, _) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: _barHeight,
                      child: CustomPaint(
                        painter: _NavBarShapePainter(
                          notchCenterX: badgeX,
                          notchCenterY: _badgeCenterY,
                          notchRadius: _badgeRadius + _notchGap,
                        ),
                        child: Row(
                          children: [
                            for (var i = 0; i < items.length; i++)
                              Expanded(
                                child: _NavItem(
                                  item: items[i],
                                  selected: i == widget.selectedIndex,
                                  onTap: () =>
                                      widget.onDestinationSelected(i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: badgeX - _badgeRadius,
                      bottom:
                          _barHeight - (_badgeCenterY + _badgeRadius),
                      child: TweenAnimationBuilder<double>(
                        // Keyed so every selection change replays the pop.
                        key: ValueKey<int>(widget.selectedIndex),
                        tween: Tween<double>(begin: 0.72, end: 1),
                        duration: const Duration(milliseconds: 460),
                        curve: Curves.easeOutBack,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: _ActiveBadge(
                          icon: items[widget.selectedIndex].selectedIcon,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The raised circle holding the active tab's icon.
class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(icon, size: 24, color: AppColors.textOnPrimary),
    );
  }
}

/// The bar's surface: a pill with a circular notch punched out wherever
/// the badge currently sits. Paints fill, hairline border and the
/// navy-tinted shadow as one shape so the notch never shows a seam.
class _NavBarShapePainter extends CustomPainter {
  const _NavBarShapePainter({
    required this.notchCenterX,
    required this.notchCenterY,
    required this.notchRadius,
  });

  final double notchCenterX;
  final double notchCenterY;
  final double notchRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(AppSpacing.radiusPill),
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(notchCenterX, notchCenterY),
          radius: notchRadius,
        ),
      )
      ..fillType = PathFillType.evenOdd;

    // Shadow first, nudged down: the blur respects the notch, so the cut
    // stays clean instead of filling with a dark disc.
    canvas.save();
    canvas.translate(0, 6);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x2E213448)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()..color = AppColors.surface,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border,
    );
  }

  @override
  bool shouldRepaint(_NavBarShapePainter old) =>
      old.notchCenterX != notchCenterX ||
      old.notchCenterY != notchCenterY ||
      old.notchRadius != notchRadius;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final FloatingNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The active icon lives in the raised badge; keeping an
              // empty box of the same height means every label stays on
              // one baseline whichever tab is selected.
              SizedBox(
                height: 29,
                child: selected
                    ? null
                    : Icon(item.icon, size: 23, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: AppTypography.caption.copyWith(
                  fontSize: 11,
                  letterSpacing: 0.1,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textTertiary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
