# Security & Privacy

## Credential storage

- Tokens live **only** in `flutter_secure_storage`:
  **iOS Keychain**, **Android EncryptedSharedPreferences**
  (`lib/core/storage/token_storage.dart`).
- Never in SharedPreferences/plain files, never in the source tree, never in
  logs. `AuthInterceptor` attaches the header from memory/cache; it never
  prints request or response bodies.
- Passwords are only ever typed into login/register forms — never stored,
  never logged, never put in URLs.
- Logout clears the whole session (access + refresh + cached user JSON) and
  the in-memory header.

## Transport

- **Production is HTTPS-only**: release builds resolve
  `https://guides-nepal.onrender.com/api/v1`; TLS verification is never
  disabled and no certificate-pinning bypass exists.
- Android `network_security_config.xml`: `cleartextTrafficPermitted="false"`
  base config; cleartext allowed **only** for `10.0.2.2`, `localhost`,
  `127.0.0.1` (dev backends). The manifest additionally sets
  `android:usesCleartextTraffic="false"`.
- iOS App Transport Security is left at the platform default (no arbitrary
  HTTP). Debug against the simulator's localhost or an HTTPS host.
- Dev URL overrides are explicit (`--dart-define=API_BASE_URL`), so a
  release build cannot silently point at an HTTP host: `AppConfig.baseUrl`
  returns the production HTTPS URL whenever `kReleaseMode`.

## Authorization model

- The app performs **no client-side privilege decisions** — role guards in
  the router are UX only. Every guide endpoint is `require_role("guide")`
  and scoped server-side to the authenticated user's id; booking queries are
  scoped to the token's user.
- No client-supplied ids are trusted for another user's data: favorites and
  trips are always read/written under the session's own token.
- Registration is hard-coded to `role: traveler` — no client role escalation.

## Error handling

- All failures map to `ApiException`; screens show friendly copy.
  Backend stack traces / `detail` payloads are never rendered raw.
- A global 401 handler ends the session instead of looping on expired
  credentials.

## Privacy & permissions

- Android permissions: `INTERNET` only — no camera, location, contacts or
  storage permissions are requested (nothing in the current feature set
  needs them).
- Data collected: account email/name, profile fields the user edits, their
  bookings/favorites, and chat content with Maila Dai. Nothing is shared
  with third-party analytics or crash SDKs (no such dependency exists in
  `pubspec.yaml`).
- No secrets or API keys are embedded in the app bundle — the AI assistant
  calls the backend proxy (`/ai/chat`), whose keys stay server-side.

## Platform notes

- `url_launcher` is declared for external links; any future external link
  must use `https://` only.
- If uploads are ever added: validate type/size client-side and re-validate
  server-side (the current profile flow does not upload files).
