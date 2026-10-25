# Testing

## Quality gates (all run on this machine, 2026-10-21)

| Command | Result |
|---|---|
| `flutter analyze` | **No issues found** (0 errors, 0 warnings, 0 infos) |
| `flutter test` | **108/108 passed** |
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
