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
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Unread items waiting on this tab (0 hides the badge).
  final int badgeCount;
}

/// Bar panel corner radius: a strongly rounded rectangle, not a full pill —
/// at this height a pill reads as a chip rather than as chrome.
const double _kBarRadius = AppSpacing.radiusXxl;

/// Diameter of the raised disc and the width of the cream halo outlined
/// around it.
const double _kBadgeDiameter = 48;
const double _kHaloWidth = 3;

/// Floating tab bar — the primary tab switcher.
///
/// The active tab lives in a raised disc that overlaps the bar's top edge;
/// the bar's outline dips into a concentric notch around it, and the disc's
/// cream halo keeps a clean ring between the two. The disc is the bar's own
/// surface carrying the glyph in brand navy — not a solid brand plate — so
/// the chrome stays quiet over photography and only the glyph plus the
/// label colour carry the active state.
///
/// Switching tabs blends three motions: the disc and notch glide to the new
/// slot together (so the notch never lags the icon), the disc pops in scale
/// as it lands, and the label fades its colour and weight.
///
/// Geometry is deliberate: layout height is identical to the earlier flat
/// bar, so screens above need no extra bottom padding — only the disc paints
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
  /// Bar height — unchanged from the earlier flat bar, so screens above
  /// need no extra bottom padding.
  static const double _barHeight = 68;

  /// Disc radius and its centre relative to the bar's top edge
  /// (negative = above it): two thirds of the disc rises over the content,
  /// the rest nests into the notch.
  static const double _badgeRadius = _kBadgeDiameter / 2;
  static const double _badgeCenterY = -8;

  /// Hairline between the disc's halo and the notch's lip, so the two never
  /// merge at fractional pixel sizes.
  static const double _notchGap = 1;

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
            // Slot centres: the same split the Row below uses, so the disc
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
                          notchRadius:
                              _badgeRadius + _kHaloWidth + _notchGap,
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
                      bottom: _barHeight - (_badgeCenterY + _badgeRadius),
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
                          badgeCount:
                              items[widget.selectedIndex].badgeCount,
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

/// The raised disc holding the active tab's icon: the bar's own surface,
/// outlined by a cream halo so it separates from the notch, with the glyph in
/// brand navy and a soft shadow lifting it off the content behind the bar.
class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.icon, this.badgeCount = 0});

  final IconData icon;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _kBadgeDiameter,
          height: _kBadgeDiameter,
          decoration: const BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowTintStrong,
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          // Inset by the halo width: the cream ring separates the white disc
          // from the bar's white surface.
          padding: const EdgeInsets.all(_kHaloWidth),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: AppColors.primary),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            right: -4,
            top: -2,
            child: _NavBadge(count: badgeCount, ringColor: AppColors.surface),
          ),
      ],
    );
  }
}

/// Unread counter drawn over a nav icon (or the active disc).
class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count, required this.ringColor});

  final int count;

  /// Colour of the gap that separates the badge from what it sits on.
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      constraints: const BoxConstraints(minWidth: 17),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: ringColor, width: 1.5),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: AppTypography.micro.copyWith(color: AppColors.textOnAccent),
      ),
    );
  }
}

/// The bar's surface: a rounded panel with a circular notch punched out
/// wherever the disc currently sits. Paints fill, hairline border and the
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
          const Radius.circular(_kBarRadius),
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
        ..color = AppColors.shadowTintStrong
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
          borderRadius: BorderRadius.circular(_kBarRadius),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The active icon lives in the raised disc; keeping an
              // empty box of the same height means every label stays on
              // one baseline whichever tab is selected.
              SizedBox(
                height: 29,
                child: selected
                    ? null
                    : Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(item.icon,
                              size: 23, color: AppColors.textTertiary),
                          if (item.badgeCount > 0)
                            Positioned(
                              right: -9,
                              top: -5,
                              child: _NavBadge(
                                count: item.badgeCount,
                                ringColor: AppColors.surface,
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: AppTypography.badge.copyWith(
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
