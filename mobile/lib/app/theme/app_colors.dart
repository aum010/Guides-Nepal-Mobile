import 'package:flutter/material.dart';

/// Guides Nepal brand palette.
///
/// Derived from the production website's Tailwind theme
/// (`frontend/tailwind.config.js`) so the app and site share one identity:
///
/// * Deep Himalayan blue `#213448` — primary text, headings, primary buttons
/// * Medium blue `#547792` — secondary elements
/// * Mist blue `#94B4C1` — tertiary accents, subtle borders
/// * Brand yellow `#F4B400` — the platform's call-to-action color
/// * Peach `#F9E6D6` / `#FFF0E6` — warm highlight surfaces
/// * Warm cream `#FDF8F5` — app background
abstract final class AppColors {
  // Brand
  static const Color primary = Color(0xFF213448); // dark blue
  static const Color primaryPressed = Color(0xFF1A2A3A);
  static const Color secondary = Color(0xFF547792); // medium blue
  static const Color tertiary = Color(0xFF94B4C1); // mist blue
  static const Color accent = Color(0xFFF4B400); // brand yellow (CTA)
  static const Color accentPressed = Color(0xFFE5A800);

  // Surfaces
  static const Color background = Color(0xFFFDF8F5); // warm cream
  static const Color surface = Color(0xFFFFFFFF); // cards
  static const Color surfacePeach = Color(0xFFFFF0E6); // warm highlight
  static const Color peach = Color(0xFFF9E6D6); // hero backgrounds
  static const Color border = Color(0xFFE7E1D8); // warm border
  static const Color shimmerBase = Color(0xFFEFE9E1);
  static const Color shimmerHighlight = Color(0xFFFAF7F2);

  // Text — a contrast-checked ramp. Every level meets WCAG AA (4.5:1) for
  // body text on both [background] and [surface]; the ratios are asserted in
  // `test/design_tokens_test.dart`, so a future palette tweak cannot quietly
  // drop below the floor.
  //
  //   textPrimary    12.1:1 on cream — headings and body
  //   textSecondary   6.7:1 on cream — supporting copy
  //   textTertiary    4.7:1 on cream — hints, metadata, placeholders
  //   textDisabled    2.4:1 — inactive controls only (WCAG 1.4.3 exempts them)
  static const Color textPrimary = Color(0xFF213448);
  static const Color textSecondary = Color(0xFF4E5A69); // was #667085 (4.7:1)
  static const Color textTertiary = Color(0xFF667085); // was #98A2B3 (2.4:1)
  static const Color textDisabled = Color(0xFF98A2B3);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnAccent = Color(0xFF213448);

  // Rating stars are meaningful glyphs, so they need 3:1 as non-text UI —
  // brand yellow (#F4B400) is only 1.9:1 on white and reads as decoration.
  static const Color iconRating = Color(0xFFB7791F);

  // Status
  static const Color success = Color(0xFF1E7B4F);
  static const Color successSurface = Color(0xFFE8F5EE);
  static const Color error = Color(0xFFC0392B);
  static const Color errorSurface = Color(0xFFFBECEA);
  static const Color warning = Color(0xFFB7791F);

  // Misc
  static const Color scrim = Color(0x66000000);
  static const Color favoriteActive = Color(0xFFE0475B);

  // Glass surfaces (frosted controls floating over photography)
  static const Color glassFill = Color(0xB3FFFFFF); // 70% white
  static const Color glassBorder = Color(0x33FFFFFF); // 20% white
  static const Color glassIcon = Color(0xFF213448);

  // Image scrims — dark-to-transparent gradients that keep white text
  // legible over any hero photo without hiding the photo itself.
  static const Color imageScrimTop = Color(0x66000000);
  static const Color imageScrimBottom = Color(0x00000000);

  // Elevation tints (shadows are always primary-tinted, never pure black,
  // so depth reads as atmosphere rather than dirt)
  static const Color shadowTint = Color(0x14213448); // 8% primary
  static const Color shadowTintStrong = Color(0x2E213448); // 18% primary

  // Overlays on photography, gradients and the brand plate.
  //
  // White-on-image needs its own ramp because it sits over unpredictable
  // content: text never drops below ~86% white and fills never rise above
  // ~22%, so a control stays legible over both a bright sky and a dark shrine.
  static const Color onImageTextPrimary = Color(0xFFFFFFFF);
  static const Color onImageTextSecondary = Color(0xDBFFFFFF); // 86% white
  static const Color onImageFill = Color(0x2EFFFFFF); // 18% white chip/circle
  static const Color onImageFillStrong = Color(0x38FFFFFF); // 22% white control
  static const Color onImageBorder = Color(0x66FFFFFF); // 40% white hairline
  static const Color onImageSurface = Color(0xF0FFFFFF); // 94% white glass pill
  static const Color onImageShadow = Color(0x2E000000); // 18% drop shadow
  static const Color ornamentFill = Color(0x12FFFFFF); // 7% decorative glow

  // Destination tile gradients (see destination_data.dart)
  static const Color tileKathmanduStart = Color(0xFF547792);
  static const Color tileKathmanduEnd = Color(0xFF213448);
  static const Color tilePokharaStart = Color(0xFF94B4C1);
  static const Color tilePokharaEnd = Color(0xFF547792);
  static const Color tileLalitpurStart = Color(0xFFB78B5E);
  static const Color tileLalitpurEnd = Color(0xFF8A5A34);
  static const Color tileBhaktapurStart = Color(0xFFC2845C);
  static const Color tileBhaktapurEnd = Color(0xFF8F4F2E);
  static const Color tileBharatpurStart = Color(0xFF6E8F6B);
  static const Color tileBharatpurEnd = Color(0xFF3F5D40);
}
