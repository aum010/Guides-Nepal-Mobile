# Testing

## Quality gates (all run on this machine, 2026-10-31)

| Command | Result |
|---|---|
| `flutter analyze` | **No issues found** (0 errors, 0 warnings, 0 infos) |
| `flutter test` | **230/230 passed** (7 design-capture cases skipped by design) |
| `flutter build apk --debug` | **Built** `build/app/outputs/flutter-apk/app-debug.apk` |
| `flutter build ios` | **Not run** — Windows host, no Xcode (see Release doc) |

Run locally:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## Suites (`test/`)

| File | Covers |
|---|---|
| `widget_test.dart` | Brand copy, formatters (`$50` vs `$49.50`, `/ person`, plural counts, relative times), booking-status parsing and `canCancel`, experience parsing (populated + minimal rows) |
| `widget_components_test.dart` | `ExperienceCard`, `AppButton` (loading blocks duplicates), empty/error states, `AppFilterChip` |
| `design_tokens_test.dart` | The palette's computable half: WCAG 2.1 contrast for every text pair and meaningful non-text pair, the emphasis ordering of the text ramp, the 4 pt spacing scale, the touch-target floor, radii ordering, and the theme wiring (canvas, CTA, disabled ink, light-only) |
| `profile_edit_test.dart` | `ProfileDraft` rules (at least one name, phone charset, length caps, trimmed payload), the `PATCH /profile/me` key spelling (`avatar_url`, never the response-side `avatarUrl`), the multipart avatar upload, and the editor: prefill, save-and-pop, live validation blocking the request, and a rejected save keeping the form |
| `design_capture_test.dart` | Design review captures, not assertions: renders the seven signed-in screens with the real theme and bundled fonts at 390×844 and writes `docs/screens/*.png`. Skipped unless `--dart-define=CAPTURE_SCREENS=true`, so nothing can flake in the normal suite |
| `onboarding_pager_test.dart` | Position indicator, `Page N of M` semantics, swipe and dot navigation, reduced-motion-safe jump, and the two account actions routing onward |
| `design_system_guard_test.dart` | The palette's discipline half: no literal colours, no Material palette colours, no hardcoded font size or family, no inline-copy growth (ratchet), and no second booking-status palette outside `BookingStatusChip` — all scanned from the real `lib/` sources |
| `sign_in_validation_test.dart` | Sign-in/sign-up field validation before any request |
| `app_router_redirect_test.dart` | `authRedirect` exhaustively: session restore, signed-out allow-list, signed-in bounce, role guard for `/guide`, `/guide/profile`, `/guide/status…` and `/guide/listing…`, public `/guide/:id` |
| `booking_flow_test.dart` | Booking form steps and the confirmation screen's destinations |
| `trips_actions_test.dart` | Trip cancel/archive against a fake API, error handling, single in-flight request, chip refresh |
| `favorites_state_test.dart` | Favorites mirror/optimistic toggle state |
| `guide_listing_editor_test.dart` | Onboarding envelope parsing, `ListingDraft` validation/serialization, create/edit/pause/delete through the real repository, pop-result contract, listings tab |
| `guide_profile_editor_test.dart` | `GuideProfileDraft` limits + completion rules + `null` serialization, editor prefill/save/validation/server rejection/load retry, workspace completion card (prompt, missing-fields wording, complete summary, retry) |
| `guide_status_test.dart` | `GuideStatusUpdate` parsing/fallbacks, `GuideStatusDraft` per-type validation (capacity pair, schedule date, message limits) and body shape, composer (announcement, capacity fields, date picker, listing link, rejection, listings failure), updates feed (empty state, type/scope/relative-time rendering, delete confirmation) |

Widget tests use a scripted `ApiClient` subclass, so the **real**
repositories, models and parsers run — no widget bypasses the network
contract, and no test hits a live backend.

## What's deliberately mocked vs real

Tests are hermetic: parsing/formatting/validation plus widget flows against a
fake transport. Repositories take an injected `ApiClient`, so HTTP is faked
without touching screens. No production accounts, no seeded server.

## Known gaps (not yet automated)

- Golden/screenshot tests for visual regressions.
- Integration tests (`integration_test/`) for startup → sign-in → explore →
  detail → booking: needs a seeded local backend; not run here.
- Nothing exercises the real FastAPI schemas — validation parity with
  `backend/app/schemas/` is reviewed by hand (and documented in
  `api-integration.md`), not executed against the server.

These are honest gaps; none of the passing claims above substitute for them.

## Regression rules

- Never delete or weaken a test to make a change pass.
- Every fix must keep `flutter analyze` at zero and `flutter test` green.
