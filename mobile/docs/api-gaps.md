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
  missing refresh token, parallel burst, non-auth failures never retried).## 2. Traveler ↔ guide messaging — IMPLEMENTED

- **Contract as built:** `GET/POST /api/v1/conversations`,
  `GET/POST /api/v1/conversations/{id}/messages`, all behind
  `get_current_user`. Opening is get-or-create on a canonical pair (low
  user id first; a unique constraint backstops the race). Messaging
  yourself is 422; unknown or inactive recipients are 404. Membership is
  enforced with **404 for both missing and non-member** threads, so ids
  cannot be probed. Fetching a thread sets `read_at` on received
  messages — that side effect is what drives the list's `unread_count`.
  Each list row carries a viewer-relative `peer` (camelCase names, as in
  `GET /profile/me`), `last_message` and `unread_count`. Bodies are
  trimmed server-side and limited to 1–2000 chars.
- **Entry point:** `BookingResponse` exposes `guide_user_id` and
  `guide_name` (the guide account assigned at booking time), so every
  live trip tile offers **Message guide**, which opens or reuses the
  thread.
- **Mobile behavior:** the Inbox tab lists real conversations — peer
  initials, preview, relative time, brand-yellow unread pill — with
  pull-to-refresh plus a 15 s poll while mounted; the thread screen
  polls every 10 s, sends inline, and clears its unread state via the
  fetch. The Maila Dai card remains as the always-available assistant.
  No fake threads, no simulated delivery.
- **Unread badge:** the Inbox tab in the floating nav bar shows the total
  unread count (capped at `9+`), on the raised badge when Inbox is active.
  It reads the same `conversationsProvider` as the list, so there is one
  fetch, and it re-fetches when the traveller switches to the tab.
- **Deliberately deferred:** SSE/push (polling is ample at current
  volumes), and guide-side workspace UI (the four routes are role-agnostic
  and already serve a guide token).

## 3. Bookmark experience id — IMPLEMENTED

- **Contract as built:** `POST /profile/bookmarks` accepts an optional
  `experience_id` (nullable int) alongside the existing
  `{title, city, image, link}` tuple, and `GET /profile/bookmarks` returns it.
  Older rows and bookmarks written by the web app have `null` there.
- **Mobile behavior:** a save sends the catalogue row's id, and
  `FavoritesController.isSaved` / `idFor` match on `experienceId` first,
  falling back to the slug in `link`. A saved experience therefore stays
  matched even if its slug is later rewritten; pre-existing rows keep working
  through the fallback. Swipe-to-remove still deletes by bookmark id.
- **Tests:** `test/favorites_state_test.dart` covers both the id match and the
  slug fallback; `backend/tests/test_profile_api.py` asserts the field
  round-trips.

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

- **Existing:** `GET /bookings/availability?date=YYYY-MM-DD[&experience_id=N]`
  → `{available, status: free|booked|reserved|full}`, plus `spots_left` when
  the query names an experience. One bucket per day, and — for a published
  guide listing — its own remaining seats (`full` means the seats, not the
  calendar, ran out).
- **Mobile behavior:** the booking flow sends the experience id with the date
  so the answer is about *that* guide and *that* trip, not the single fallback
  catalogue guide. The guest stepper stops at `spots_left`, a sold-out listing
  disables the booking bar, and a `full` day explains the seats are gone. There
  is still no time-picker because the API has no time-slot data. Availability
  failures are advisory — the server's `POST /bookings/` validation is
  authoritative.
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
- **Public updates — IMPLEMENTED:** `GET /updates?city=&limit=` returns the
  active, current rows (newest first, `booking` notes excluded, city matched
  through the listing or the guide's profile). "Current" is judged in Nepal
  time (UTC+05:45), so an update does not linger past its day while the
  server's clock is still on the previous UTC date. See
  `backend/app/services/guide_dashboard_service.py`.
- **Public guide profile — IMPLEMENTED:** `GET /guides` merges the legacy
  catalogue rows with real guide accounts that finished onboarding, and
  `GET /guides/{id}` resolves either. Guide accounts use a namespaced id
  (`300000 + user id`) so they can never shadow a catalogue row; the payload
  carries the onboarding display name, bio, cities and languages, and a rating
  pooled from their published trips. `verified` stays `false` — the platform
  records no verification for guide accounts, so the badge is not implied.
- **Listings are traveller-visible — IMPLEMENTED:** an active listing is a
  catalogue row at `GET /experiences` (`id = 200000 + listing id`,
  `slug = listing-<slug>`) with its guide as host, and at
  `GET /experiences/listing-<slug>`. `category` is mapped onto the public
  values the Explore chips filter by (`trekking → Adventure`, `tour →
  Cultural`, `specialized → Workshop`), and the row carries `difficulty`,
  `meetingPoint`, `itinerary`, `maxGuests` and `availableSpots`. Pausing a
  listing removes it (and its detail page) immediately.
- **Booking reaches the right guide — IMPLEMENTED:** `POST /bookings/` with a
  listing's catalogue id assigns the guide who owns it, records
  `guide_listing_id`, and takes the seats; cancelling or the guide declining
  gives them back exactly once. Seeded content still routes to the single
  catalogue guide. `BookingCreate.guests` is bounded 1–100 because it now
  moves a seat count.
- **Approval workflow routes exist:** `/experience-workflow/proposals`,
  `/queue/proposals`, `/change-requests`, `/queue/change-requests` and their
  decision endpoints (proposal gate: regional-head or content-manager;
  change-request gate: regional-head only). Publishing an approved proposal
  creates the same live listing the catalogue serves. The app does not yet
  surface this workflow — a guide edits listings directly.
- **Listing photos — IMPLEMENTED:** `POST /guide/listings/{id}/photo` takes
  a JPEG/PNG/WebP up to 5 MB, validates the bytes (not the filename), stores
  it under `/uploads/listings/{id}/` and returns the listing with
  `hero_image`. Replacing it deletes the old file; clearing it
  (`PATCH {"hero_image": null}`) or deleting the listing removes it too. A
  URL cannot be set directly — only an uploaded file. The catalogue card and
  detail page use it, falling back to a category photo when a guide has not
  added one. The app picks from the photo library, downscales to 1600 px and
  uploads after the listing is saved.
- **Still missing:** earnings/payouts, performance metrics and availability
  calendars.
- The app never presents any of the unbuilt pieces as available.

## 9. Listing slugs

- A listing's slug is generated once at create time (`annapurna-base-camp-trek`,
  `-2` on collision) and **never regenerated on rename**, so a shared link keeps
  working. `GET /guide/listings` returns it as `slug` / `public_slug` with
  `is_public`; the listings card shows a `Live` chip for an active row and
  `Paused` otherwise.

## 10. Misc

- No pagination on `/experiences`, `/bookings`, `/bookmarks` — the app
  fetches full lists; fine at current data volumes, will need
  `?page&per_page` later.
- `POST /profile/photos/upload` returns a relative `/uploads/{id}/{file}`
  URL; the app resolves such paths with `AppConfig.resolveMedia`, and avatar
  upload is now wired end to end in `/profile/edit` (pick → upload → store the
  path).
- **`PATCH /profile/me` reads `avatar_url`, not `avatarUrl`.** The response
  object spells it camelCase, and `ProfileUpdate` silently ignores unknown
  keys — sending the response spelling returns 200 and stores nothing. Pinned
  by `test/profile_edit_test.dart`. Upload validation and the served directory are shared with
  listing photos (`backend/app/core/storage.py`).- No server-side avatar for hosts on seeded rows — profile shows initials fallback rather than a fabricated photo.

## 11. Password reset and change — IMPLEMENTED (delivery caveat)

- **Contract as built:** `POST /auth/forgot-password` → `{email}` → 200 with
  one generic `{message}` whether or not the address is registered (the
  endpoint is built to prevent user enumeration). The backend sends the reset
  email itself through the Supabase Admin API; with no Supabase credentials it
  still returns 200 and only logs that it could not send.
- **Mobile behavior:** `/forgot-password` posts the email and renders the
  server's own message — it never states that the address exists and never
  claims delivery on its own. Because a deployment without mail configured
  cannot deliver, the confirmation also carries an honest note and a
  **Contact support** link. `POST /auth/change-password`
  (`current_password`, `new_password`) backs `/settings/password`, reachable
  from Profile → Account; the server's 400 detail ("Current password is
  incorrect") is shown verbatim.
- **Tests:** `test/forgot_password_test.dart` (validation, trimmed email,
  server message shown, backend failure surfaced).
- **To close the caveat:** configure `SUPABASE_URL` +
  `SUPABASE_SERVICE_ROLE_KEY` + `RESET_PASSWORD_REDIRECT_URL` on the backend,
  or add a mobile deep-link reset route.

## 12. Host workspace — IMPLEMENTED (three gaps, stated in-app)

- **Role boundary:** `host` is self-registerable and separate from `guide`
  (`backend/app/core/roles.py`). Every `/host/*` route runs `current_host`,
  which answers 403 unless the account's role is exactly `host` and scopes all
  queries to that host.
- **Implemented:** `/host` opens a three-tab console — **Experiences**
  (`GET|POST /host/experiences`, `PATCH|DELETE /host/experiences/{id}`),
  **Tours** (`GET|POST /host/tours`, `PATCH|DELETE /host/tours/{id}`) and
  **Bookings** (`GET /host/bookings`, `PATCH /host/bookings/{id}` with
  `accepted|rejected`). Both editors validate against the server's
  `HostExperienceCreate` / `HostTourCreate` constraints before a round trip.
- **Deliberately not offered:**
  - `POST /host/bookings` — a host entering an off-platform booking by hand is
    a desk task, not a phone one; the endpoint exists but no UI reaches it.
  - Marking a booking `completed` — `PATCH` accepts only `accepted`/`rejected`,
    so the app does not present a state the server would refuse.
  - Toggling `is_active` on a host experience/tour — the response carries the
    flag but no host route can change it, so the app shows Active/Inactive and
    never a switch that would 404.
  - Earnings, payouts and performance — no `/host/*` endpoint returns them.
- **Host approval is enforced at login, not in the app:**
  `AuthService.authenticate_user` refuses a `host` row with no approved
  `host_applications` row ("Your host account is not active yet…"), and
  approval is the only moment a host login is minted
  (`operations.review_host_application` → `_provision_host_user`). So the
  workspace is reachable only by an approved host, and the app adds no
  approval claim of its own — it simply shows the role the backend reports.
  There is no mobile host-application form; applying stays on the website
  (`POST /host-applications[/submit]`), and mobile signup remains
  traveler-only.
- **Tests:** `test/host_models_test.dart` (wire parsing, validation mirrors,
  booking decision rules), `test/app_router_redirect_test.dart` (host vs
  traveler vs guide guards).
