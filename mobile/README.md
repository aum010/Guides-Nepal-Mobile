# Guides Nepal — Mobile App

**Discover Nepal Through Local Eyes.** A Flutter app (Android + iOS) for
discovering experiences, guides and destinations across Kathmandu, Pokhara,
Lalitpur, Bhaktapur and Bharatpur — with booking, trips, server-synced
favorites and the Maila Dai AI travel assistant.

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
flutter test      # 108 tests: parsing, formatters, guards, widget flows
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
├── l10n/app_strings.dart   # all user-facing copy (Nepali-ready)
└── shared/                 # models, reusable widgets
test/                       # unit + widget tests (108)
docs/                       # architecture, design system, API, security,
                            # testing, release docs
```

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
