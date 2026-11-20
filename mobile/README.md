# Guides Nepal — Mobile App

**Discover Nepal Through Local Eyes.** A Flutter app (Android + iOS) for
discovering experiences, guides and destinations across Kathmandu, Pokhara,
Lalitpur, Bhaktapur and Bharatpur — with booking, trips, server-synced
favorites, messaging, the Maila Dai AI travel assistant, a guide workspace and
a separate host workspace for the `host` role.

## Prerequisites

- Flutter 3.47.x / Dart 3.13.x (see `pubspec.yaml` SDK constraint)
- Android: Android SDK + NDK `28.2.13676358` (Flutter pins this; it
  auto-installs on first build)
- iOS: macOS with Xcode 15+ (CocoaPods Podfile is generated on first build)
- A running Guides Nepal backend (repo root `backend/`), or the production API

## Getting started

```bash
cd mobile
flutter pub get
flutter run                    # picks the right dev API base automatically
```

Dev API base resolution (`lib/core/config/app_config.dart`):

| Target              | Base URL                              |
|---------------------|---------------------------------------|
| Android emulator    | `http://10.0.2.2:8000/api/v1`         |
| iOS simulator       | `http://localhost:8000/api/v1`        |
| Physical device     | pass `--dart-define=API_BASE_URL=http://<LAN-IP>:8000/api/v1` |
| Release builds      | `https://guides-nepal.onrender.com/api/v1` (HTTPS, always) |

Override for any build:

```bash
flutter run --dart-define=API_BASE_URL=https://staging.example.com/api/v1
```

Start the backend from the repo root (see root `README.md` / `run-project.*`),
then `flutter run` on an emulator or device.

## Quality gates

```bash
flutter analyze   # must report "No issues found"
flutter test      # 230 tests: parsing, formatters, guards, widget flows
flutter build apk --debug     # Android (verified on this machine)
flutter build ios --release   # macOS + Xcode only
```

## Project layout

```
lib/
├── main.dart               # ProviderScope entrypoint
├── app/                    # app shell, router (GoRouter + guards), theme
├── core/                   # config, network (Dio + auth interceptor),
│                           # secure storage, utils
├── features/               # feature-first screens + controllers + repos
│                           # (auth, home, explore, experiences, bookings,
│                           #  trips, favorites, inbox, ai_assistant, guide_tools,
│                           #  host_tools, profile, help …)
├── l10n/app_strings.dart   # all user-facing copy (Nepali-ready)
└── shared/                 # models, reusable widgets
test/                       # unit + widget tests (230)
docs/                       # architecture, design system, API, security,
                            # testing, release docs
```

## Branding

The launcher icon, the launch screen and the in-app logo all come from the
supplied logo package. Icon and splash masters are committed under `brand/`
(build-time only, not bundled); the two images the UI draws are in
`assets/brand/`. The rounded plate is the Android icon, a squared no-alpha
plate is the iOS icon, the full lockup is the launch screen, and the circular
mark is the in-app logo (`AppLogoMark`).

```bash
dart run flutter_launcher_icons          # regenerate platform launcher icons
dart run flutter_native_splash:create    # regenerate the OS splash
```

Both generators are dev dependencies configured at the bottom of
`pubspec.yaml`; [docs/design-system.md](docs/design-system.md#brand-artwork)
explains why the iOS icon has no alpha and why the Android 12 splash logo
cannot be widened.

## Accounts and workspaces

| Role | What the app gives it |
|---|---|
| `traveler` (default signup) | Home · Explore · Trips · Inbox · Profile, booking, favorites, reviews, Maila Dai |
| `guide` | Everything above plus **Guide tools** (`/guide`): onboarding, listings, capacity, requests, updates |
| `host` | Everything above plus **Host tools** (`/host`): owned experiences, tours and booking requests |

Host and guide are different server roles and neither workspace opens for the
other. A host cannot sign in until a regional-head/admin approves the host
application — the backend enforces that at login, so the app never needs to
guess. Every `/guide/*` and `/host/*` request is authorized server-side; the
router guards are convenience only.

## Password reset

`/forgot-password` posts to `POST /auth/forgot-password`, which emails the
reset link itself (Supabase Admin API) and answers with one generic message.
The screen shows the server's wording, never claims an address exists, and
points at support when a deployment has no mail service configured — see
[docs/api-gaps.md](docs/api-gaps.md#11-password-reset-and-change--implemented-delivery-caveat).
Signed-in users change their password from Profile → Account (`POST
/auth/change-password`).

## Documentation

- [docs/architecture.md](docs/architecture.md)
- [docs/design-system.md](docs/design-system.md)
- [docs/api-integration.md](docs/api-integration.md)
- [docs/api-gaps.md](docs/api-gaps.md) — backend capabilities the app cannot use yet
- [docs/security.md](docs/security.md)
- [docs/testing.md](docs/testing.md)
- [docs/release.md](docs/release.md)

## Troubleshooting

- **Build fails with NDK not found** — run `flutter doctor` or let Gradle
  auto-install NDK `28.2.13676358`, or temporarily set
  `ndkVersion = "27.1.12297006"` in `android/app/build.gradle.kts`.
- **Requests fail from a physical device** — the device cannot reach your
  machine's `localhost`; pass `API_BASE_URL` with your LAN IP and make sure
  the backend listens on `0.0.0.0`.
- **Signed out right after login** — check you are pointing at a backend whose
  schema matches the app (see `docs/api-gaps.md`).
