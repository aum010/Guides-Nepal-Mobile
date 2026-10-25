# API Gaps & Unsupported Functionality

Verified against `backend/app/api/v1/` on 2026-10-20. Everything below is a
capability the product would want that the backend does not (yet) expose. No
endpoint in this app is invented — gaps are either honestly presented as
unavailable or use a documented workaround.

## 1. Token refresh — IMPLEMENTED (restore-time)

- **Contract as built:** `POST /api/v1/auth/refresh` → `{refresh_token}` →
  200 `{access_token, refresh_token, token_type, user}` (same `Token` shape
  as login, so the client persists it with the existing code path). The
  refresh token is a JWT of type `refresh`; an access token, a tampered
  token or a token for an inactive user is rejected **401**. Tokens rotate
  on every exchange. Access tokens live `ACCESS_TOKEN_EXPIRE_MINUTES`
  (30 min); refresh tokens `REFRESH_TOKEN_EXPIRE_DAYS` (7 days).
- **Mobile behavior:** `AuthRepository.restoreSession` validates the cached
  access token against `GET /profile/me`; on 401 it exchanges the stored
  refresh token and continues the session. Only a rejected refresh token
  clears secure storage and signs the user out. Missing refresh token → no
  network call, clean sign-out. Unit tests:
  `test/auth_refresh_test.dart`.
- **In-session renewal:** `AuthInterceptor` recovers a 401 transparently —
  it exchanges the refresh token (single-flight, so a burst of parallel
  401s shares one exchange) and replays the request once with the rotated
  access token. Only a rejected refresh fires `onUnauthorized` and ends the
  session. Tests: `test/auth_interceptor_test.dart` (replay, rejection,
  missing refresh token, parallel burst, non-auth failures never retried).

## 2. Traveler ↔ guide messaging — MISSING (Inbox is honest)

- **Required:** conversation list, thread history, send, unread counts for
  the Inbox tab.
- **Existing:** none — no `/conversations` or `/messages` routes anywhere in
  `backend/app/api/v1/`.
- **Mobile behavior:** the Inbox tab states "Direct messaging with guides is
  coming soon" and routes to Maila Dai. No fake threads, no simulated
  delivery.
- **Recommended contract:** `GET/POST /conversations`,
  `GET /conversations/{id}/messages`, `POST …/messages` with
  `require_auth`, scoped membership checks; polling at 10–15 s or SSE for
  real-time.

## 3. Bookmarks have no experience id — CONTRACT LIMITATION

- **Existing:** `POST /profile/bookmarks` stores a free-form
  `{title, city, image, link}` tuple; there is no `experience_id` field.
- **Workaround (implemented):** the app writes the experience **slug** into
  `link` and matches on it for de-dupe and "is saved" checks
  (`FavoritesController.isSaved`). Swipe-to-remove deletes by bookmark id.
- **Risk:** if the web app writes different `link` values, those bookmarks
  still display but may not map to a detail route.
- **Recommendation:** add `experience_id` (nullable int) to the bookmark
  schema; the mobile model already parses tolerantly and would pick it up.

## 4. Sign-out revocation — IMPLEMENTED (refresh tokens)

- **Contract:** `POST /api/v1/auth/logout` → `{refresh_token}` → 200
  `{status: "ok"}`. It always answers 200 (idempotent; an unreadable or
  already-expired token is ignored), so a client can sign out safely.
- **Mechanism:** every refresh token carries a unique `jti`; logout records
  it in `revoked_tokens` (rows pruned as they expire) and `/auth/refresh`
  rejects a revoked `jti` with 401. Revocation is per-session — another
  device's refresh token keeps working. Refresh tokens minted before `jti`
  support carry no id; they cannot be revoked and simply expire (≤7 days).
- **Sign out everywhere:** `POST /api/v1/auth/logout-all` (authenticated)
  bumps both counters — `token_version` kills every access token and
  `session_version` kills every refresh token issued so far. Exposed on
  Profile as "Sign out of all devices"; the client calls it, then clears
  locally. A later sign-in mints tokens at the new versions.
- **Mobile behavior:** `AuthRepository.logout` posts the stored refresh
  token before clearing storage; a failed call (offline) still signs the
  user out locally.
- **Access tokens too:** every access token carries the user's
  `token_version` as a `ver` claim, checked on each authenticated request
  (one shared authenticator now backs `/profile` and `/host` as well as
  `get_current_user`). Signing out bumps the counter, so already-issued
  access tokens are refused **immediately** with 401 "Your session has
  ended." Other devices are not signed out: their refresh tokens stay valid
  and the client renews on the next 401.
- **Trade-off:** the version is global per user, so a sign-out burns the
  access tokens of every device, while refresh tokens are revoked per
  session. Fully independent sessions would need a per-session token id.

## 5. OAuth is web-only — NOT USABLE FROM MOBILE

- **Existing:** `/auth/oauth/{google,facebook}/start` → provider →
  `/auth/oauth/…/callback` which redirects to `settings.FRONTEND_OAUTH_REDIRECT`
  **with tokens in query params** — designed for the website.
- **Mobile behavior:** Google/Facebook sign-in buttons are **not shown**.
  Email/password is the complete, working flow. No fake OAuth UI.
- **To support mobile:** add a deep-link (or universal-link) callback
  variant, e.g. `redirect_uri=https://guidesnepal.app/oauth/callback` or an
  `?client=mobile&redirect=<app-scheme>` mode, and prefer Authorization Code
  + PKCE over tokens-in-query.

## 6. Availability is day-level, not time slots

- **Existing:** `GET /bookings/availability?date=YYYY-MM-DD` →
  `{available, status: free|booked|reserved}` — one bucket per day.
- **Mobile behavior:** the booking flow checks the chosen day before
  proceeding and tells the user to pick another date if unavailable; there is
  no time-picker because the API has no time-slot data. Availability failures
  are advisory — the server's `POST /bookings/` validation is authoritative.
- **To support time slots:** per-slot availability endpoint + `time` field on
  `BookingCreate`.

## 7. No payment step

`POST /bookings/` creates a booking directly (`upcoming`). The app therefore
shows **"Your guide will confirm this request. You are not charged now."**
and never fakes payment UI or success screens.

## 8. Guide-side gaps

- Backend routes verified: `GET /guide/me|bookings|dashboard|onboarding|
  listings|status`, `POST|PATCH|DELETE /guide/listings…`,
  `PATCH /guide/bookings/{id}`, `PUT /guide/onboarding`,
  `POST|DELETE /guide/status` — all `require_role("guide")`, scoped to the
  signed-in guide.
- **Implemented in the app:** profile onboarding, dashboard (profile card +
  stats + listings), the updates feed and composer, booking requests with
  accept/decline, capacity editing, and full listing management — create
  (`POST /guide/listings`), edit
  (`PATCH /guide/listings/{id}`), pause/resume (`is_active`) and delete
  (`DELETE /guide/listings/{id}`). Form validation mirrors the server
  schemas (`GuideListingCreate`, `GuideListingUpdate`,
  `GuideOnboardingCreate`); a listing the guide does not own loads as
  "no longer available" rather than a blank form, and a profile that fails
  to load offers a retry instead of an empty draft that would overwrite it.
- **`GET|PUT /guide/onboarding` semantics:** the GET envelope is
  `{onboarding, completed}`, and `onboarding` is `null` for a guide who never
  onboarded — the app treats that as an empty draft, not an error. PUT
  replaces the stored profile, so the wizard always sends the whole form.
  `onboarding_completed` is only a flag the guide sets: the server stores it
  without checking that the profile has a name, cities, languages or a bio,
  so the app enforces those locally and saves a draft while the switch is
  off.
- **`GET|POST|DELETE /guide/status` semantics:** the list is newest-first
  (`?limit`, 1–100, default 20). `POST` returns the created row, and a
  `listing_id` the guide does not own fails **404** instead of detaching —
  the composer surfaces that inline with the text intact. `update_type` is one
  of `announcement | availability | capacity | booking | schedule`;
  `event_date`, `area`, `current_capacity` and `max_capacity` are free-form
  extras, so the app only shows capacity fields for a `capacity` update, the
  date for `schedule`, and validates `booked <= total` client-side (the server
  does not cross-check them). `DELETE` removes the row for good.
- **Missing backend capability — updates are not public either:** no route
  outside `/guide/status` returns `GuideStatusUpdate` rows, so an
  announcement, availability note or schedule change never reaches
  travellers. The composer says so rather than implying a feed exists.
  A public `GET /guides/{id}/updates` (active rows, `event_date >= today`)
  would be the natural shape.
- **Missing backend capability — the guide profile is not public:**
  `GET /guides/{id}` is served by `GuideService` from the legacy `guides`
  table, not from `guide_profiles`, so the onboarding data a guide saves here
  is currently visible only inside the phone's workspace. Joining
  `guide_profiles` into `GuideResponse` is what would make it reach
  travellers.
- **Missing backend capability — guide listings are not traveller-visible:**
  `guide_listings` rows are returned by `/guide/listings` only; `/experiences`
  serves seeded content and `POST /bookings/` books an experience. The repo
  models an approval flow (`app/models/experience_workflow.py`,
  `experience_workflow_service.py`) that would turn an approved listing into
  a live experience, but **no routes exist** for it. Until they do, the app
  says "Save listing" (not "Publish") and the listings empty state does not
  promise traveller reach.
- **Missing backend capability:** earnings/payouts, performance metrics,
  availability calendars for guides.
- The app never presents any of the unbuilt pieces as available; a guide
  sees the dashboard, requests and listings only.

## 9. Misc

- No pagination on `/experiences`, `/bookings`, `/bookmarks` — the app
  fetches full lists; fine at current data volumes, will need
  `?page&per_page` later.
- `POST /profile/photos/upload` returns a relative `/uploads/{id}/{file}`
  URL; the app does not yet wire avatar upload (no absolute-URL resolution
  guarantee documented).
- No server-side avatar for hosts on seeded rows — profile shows initials
  fallback rather than a fabricated photo.
