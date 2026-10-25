# Build & Release

## Environment configuration

| Build | API base | Cleartext |
|---|---|---|
| Debug (emulator/device) | auto: `10.0.2.2:8000` / `localhost:8000` | dev hosts only (Android network security config) |
| Any build + `--dart-define=API_BASE_URL=…` | your override | only if override is `http://` **and** it's a dev host |
| Release | `https://guides-nepal.onrender.com/api/v1` | never |

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://staging.example.com/api/v1
```

## Android

Verified commands (Windows):

```bash
flutter pub get
flutter build apk --debug      # ✅ verified on this machine
flutter build appbundle --release
```

Prerequisites & signing:

1. Android SDK + NDK `28.2.13676358` (Flutter pins it; auto-installs).
   Fallback for machines without it: set `ndkVersion = "27.1.12297006"` in
   `android/app/build.gradle.kts`.
2. **Release still signs with the debug keystore** (Flutter template
   default, `build.gradle.kts` TODO). Before Play submission:
   - `keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
   - create `android/key.properties` (never commit it) with
     `storeFile`, `storePassword`, `keyAlias`, `keyPassword`
   - wire `signingConfigs.release` and point `buildTypes.release` at it.
3. App identity: `applicationId com.guidesnepal.guides_nepal`, launcher name
   **Guides Nepal** (`res/values/strings.xml`).

Play Store checklist: versionCode/versionName from `pubspec.yaml`
(`0.1.0+1`) · 512px icon · feature graphic · screenshots (phone) · privacy
policy URL (app collects account + booking data, no third-party SDKs) ·
data-safety form matching `docs/security.md` · target API level from
`flutter.targetSdkVersion`.

## iOS

Validated statically on this host (config only):

- Bundle id `com.guidesnepal.guidesNepal`, display name **Guides Nepal**,
  deployment target **iOS 15.0**, ATS at platform default (HTTPS-only),
  portrait + landscape declared.

Build (requires macOS + Xcode — **not run here; Windows host**):

```bash
flutter build ios --release        # then archive in Xcode
# CocoaPods Podfile is generated on first `flutter build ios` / `flutter run`
```

App Store checklist: Apple Developer account + signing team ·
`flutter build ipa` or Xcode archive · App Privacy label (account data,
no tracking) · screenshots for required device classes · review notes
(demo login or test account if moderation needs it).

## Pre-release gates

```bash
flutter analyze      # zero issues
flutter test         # all green
flutter build apk --debug
```

Do not ship if any gate regressed. Report iOS as *unverified* until an
actual `xcodebuild`/`flutter build ios` succeeds on macOS.

## Post-release

- Bump `version:` in `pubspec.yaml` (`MAJOR.MINOR.PATCH+BUILD`).
- Tag the repo commit that produced the build.
- Smoke-test the release build against production: sign-in, explore,
  booking request, favorites, Maila Dai.
