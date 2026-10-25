# Design System

Tokens live in `lib/app/theme/` (`app_colors.dart`, `app_spacing.dart`,
`app_typography.dart`, `app_theme.dart`); components in `lib/shared/widgets/`.

## Brand colors

Derived from the website's Tailwind theme so site and app share one identity.

| Token | Hex | Use |
|---|---|---|
| primary | `#213448` | deep Himalayan blue — headings, dark surfaces |
| secondary | `#547792` | medium blue — secondary elements, links |
| tertiary | `#94B4C1` | mist blue — placeholders, subdued icons |
| accent | `#F4B400` | brand yellow — primary CTA fill (with `#213448` text) |
| background | `#FDF8F5` | warm cream app background |
| surface | `#FFFFFF` | cards, sheets, input fills |
| surfacePeach / peach | `#FFF0E6` / `#F9E6D6` | warm highlights, chips, hero |
| border | `#E7E1D8` | warm hairline borders |
| textPrimary / Secondary / Tertiary | `#213448` / `#667085` / `#98A2B3` | type hierarchy |
| success / error / warning | `#1E7B4F` / `#C0392B` / `#B7791F` | status (+ tinted surfaces) |
| favoriteActive | `#E0475B` | saved heart |

No pure black anywhere; white is used for cards only, not as page
background. No decorative gradients — the Home hero and destination header
use the two brand blues as an editorial block.

## Typography

- **PlayfairDisplay** (bundled, SIL OFL) — editorial display: `displayLarge/Medium/Small`.
- **Inter** (bundled, SIL OFL) — all UI: `h1–h3`, `title`, `subtitle`, `body`,
  `small`, `caption`, `label`, `overline`, plus numeric `price`/`priceLarge`.

Variable-font `wght` axis set explicitly via `FontVariation`. Never hardcode
font sizes in screens — always use `AppTypography.*`.

## Spacing & radii

Scale: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64` (`AppSpacing.x1…x16`),
`gutter = 20` for screen padding, `minTouchTarget = 44`.

Radii: `sm 8` (inputs, small images) · `md 12` (buttons, fields, list tiles) ·
`lg 16` (cards) · `xl 20` (hero blocks, dialogs) · `pill 999` (chips,
search). Buttons are 12, cards 16 — nothing is a pill by default.

## Components (`lib/shared/widgets/`)

| Component | States / notes |
|---|---|
| `AppButton` | primary (yellow) / secondary (blue) / outline / ghost; **loading** state blocks double-submit; min 44dp targets; `expanded` |
| `AppTextField` | label, error text, password reveal toggle, semantics |
| `ExperienceCard` | 4:3 image, save heart (never covers title), meta line, rating row, per-person price; accessible label reads title/city/rating/price |
| `GuideCard` / `GuideAvatar` | portrait with initials fallback |
| `NetworkImageView` | cache + shimmer placeholder + error fallback, `maxWidthDiskCache: 1600` |
| `SectionHeader` | title + optional action |
| `AppFilterChip` / `InfoChip` | selected + unselected |
| `SkeletonBox` / `SkeletonList` | shimmer loading (respects reduced motion) |
| `EmptyStateView` / `ErrorStateView` | icon + copy + optional action / retry |

Interactions: hearts animate and reconcile with the server; bottom sheets and
dialogs come from the theme; `pageTransitionsTheme` uses Cupertino
transitions on **both** platforms for a native feel. Animations are disabled
under reduced-motion (`MediaQuery.disableAnimationsOf`).

## Accessibility

- Touch targets ≥ 44dp (`minTouchTarget`), navigation bar height 64.
- Screen-reader semantics on cards, hearts, images, buttons.
- Text scaling left at system default; type uses `height` for reflow.
- Contrast: `#213448` on cream/white ≥ 7:1; CTA is `#213448` on `#F4B400`.
- Light theme only — dark mode ships only when it can be done coherently
  (documented decision, not an oversight).

## Conventions

All user-facing copy lives in `AppStrings` — no literal UI strings in
widgets. Status chips map booking states → color pairs in one place per
screen family.
