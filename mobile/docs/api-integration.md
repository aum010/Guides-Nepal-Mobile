# API Integration

## Base URL

Single source of truth: `lib/core/config/app_config.dart` — feature code
never holds URLs.

1. `--dart-define=API_BASE_URL=…` (any build: staging / LAN device)
2. Release builds → `https://guides-nepal.onrender.com/api/v1` (verified
   production API)
3. Debug builds → `10.0.2.2:8000` (Android emulator) or `localhost:8000`
   (iOS simulator / desktop)

Cleartext HTTP exists **only** for dev hosts and debug builds
(`android/app/src/main/res/xml/network_security_config.xml`; the manifest
sets `android:usesCleartextTraffic="false"`). iOS ATS stays at platform
default (blocks arbitrary cleartext); use the simulator's localhost or HTTPS.

## Client

One Dio instance (`ApiClient`, `lib/core/network/api_client.dart`):

- Timeouts: connect 15 s · receive 30 s · send 20 s.
- `AuthInterceptor` attaches `Authorization: Bearer …` (cached token, async
  secure-storage fallback), and fires `onUnauthorized` on any 401 so the
  session ends app-wide.
- Every `DioException` is normalized exactly once by
  `ApiClient.mapDioException` → `ApiException(kind, statusCode, message,
  fieldErrors)`. FastAPI 422 payloads become `{field: message}`.
- **No automatic retries.** Reads may be re-fetched via UI retry buttons;
  `POST /bookings/` is never retried — the booking flow guards with
  `_submitting`/`_submitted` flags so double-taps can't duplicate bookings.
- Requests carry `CancelToken`s; Explore cancels in-flight searches when
  filters change.

## Authentication

| Flow | Endpoint | Notes |
|---|---|---|
| Register | `POST /auth/register` | sends `role: traveler` (backend allow-lists) |
| Login | `POST /auth/login` | returns `access_token`, `refresh_token`, `user` |
| Session | `GET /profile/me` | validates stored session on startup |
| Logout | local | clears secure storage + cached token (server has no revocation endpoint) |
| Password | `POST /auth/change-password` | wired in `AuthRepository` |
| OAuth | — | backend redirects OAuth callbacks to the **web** frontend; not usable from mobile without backend changes (see api-gaps.md) |

Tokens are stored **only** in `flutter_secure_storage` (Keychain /
EncryptedSharedPreferences), never in SharedPreferences or logs.

## Endpoint map (all verified against `backend/app/api/v1/`)

```
GET    /experiences?city&category&search&min_price&max_price&sort
GET    /experiences/{slug}
GET    /guides?city            GET /guides/{id}
GET    /reviews/?experience_id GET /reviews/can-review   POST /reviews/
GET    /bookings/availability?date
GET    /bookings/              POST /bookings/
POST   /bookings/{id}/cancel   POST /bookings/{id}/archive
GET    /profile/me             PATCH /profile/me
GET    /profile/bookmarks      POST /profile/bookmarks   DELETE /profile/bookmarks/{id}
POST   /ai/chat                POST /ai/chat/stream
GET    /guide/me               GET /guide/dashboard      GET /guide/bookings
PATCH  /guide/bookings/{id}    GET /guide/listings        POST /guide/listings
PATCH|DELETE /guide/listings/{id}   PATCH /guide/listings/{id}/capacity
GET|PUT /guide/onboarding      GET|POST /guide/status     DELETE /guide/status/{id}
POST   /auth/register|login|change-password|forgot-password
```

### Guide profile (`/guide/onboarding`)

`GET` returns `{onboarding, completed}`; `onboarding` is `null` for a guide
who never onboarded and the app renders an empty draft rather than an error.
`PUT` replaces the stored profile, so the editor always sends the whole form
(`GuideProfileDraft.toProfile()`), with cleared optional text sent as `null`.

`onboarding_completed` is a claim the guide makes — the server stores it
without checking that the profile is filled in — so the switch is gated
locally on name, expertise, cities, languages and bio, and with it off the
form saves as a draft. The profile is currently workspace-only:
`GET /guides/{id}` still serves the legacy `guides` table (see
`api-gaps.md`).

### Guide updates (`/guide/status`)

`GET` (newest first, `?limit=1…100`, default 20), `POST` (201 with the created
row) and `DELETE /guide/status/{id}`. `update_type` is one of
`announcement | availability | capacity | booking | schedule`; `area`,
`event_date`, `current_capacity` and `max_capacity` are optional. The app
sends capacity numbers only with `capacity` and the ISO 8601 date only with
`schedule`, and enforces `booked <= total` itself (the server does not).
An unowned `listing_id` is rejected with 404 and shown inline — the drafted
update is never lost.

Nothing outside `/guide/status` reads these rows, so updates are
workspace-only; the composer states that (`api-gaps.md`).

## Models

`lib/shared/models/` — parsers are defensive (`as num? ?? fallback`,
`is Map` checks) because seeded content rows omit optional fields that live
host rows include. Unknown/missing booking status falls back to `upcoming`
rather than throwing.

## Currency

Prices are displayed exactly as the backend's booking currency (USD,
`Formatters.bookingCurrency*`) and labeled `/ person` — no exchange-rate
conversion is ever invented client-side.
