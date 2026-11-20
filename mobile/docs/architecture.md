# Architecture

## Stack

Flutter 3.47 / Dart 3.13 · Riverpod (state) · GoRouter (navigation) ·
Dio (HTTP) · flutter_secure_storage (credentials).

## Layers

Feature-first; each feature holds only the layers it needs:

```
Screen (ConsumerWidget/StatefulWidget)
  └─► Controller / provider (Riverpod Notifier, FutureProvider, StateNotifier)
        └─► Repository (contract-typed API access)
              └─► ApiClient (single Dio instance + AuthInterceptor)
                    └─► Backend /api/v1
```

- **Presentation** — widgets never call Dio directly; they watch providers and
  call controllers. All copy comes from `lib/l10n/app_strings.dart`.
- **State** — Riverpod only. Global session lives in
  `authControllerProvider`; per-screen data uses `FutureProvider.autoDispose`
  families (e.g. `experienceDetailProvider(slug)`).
- **Data** — repositories translate verified backend contracts into typed
  models (`lib/shared/models/`). Parsing is defensive: optional server fields
  never crash a screen.

## State management

| Kind                  | Used for                                   |
|-----------------------|--------------------------------------------|
| `Notifier`            | session (`AuthState`), favorites mirror    |
| `StateNotifier`       | Explore filters (search/city/category)     |
| `FutureProvider`      | all reads (experiences, trips, dashboard…) |
| `StateProvider`       | tiny ephemeral UI state (debounced search) |

Optimistic updates are used only for favorites, with automatic revert if the
server rejects — a save that failed is never shown as saved.

## Navigation

`lib/app/router/app_router.dart` — GoRouter with a `redirect` guard:

1. `AuthStatus.restoring` → hold on `/splash` (session validated against
   `GET /profile/me`).
2. Signed out → only `/sign-in`, `/sign-up`, `/onboarding`, `/splash`.
3. Signed in → `/sign-in|/sign-up` bounce to `/home`.
4. **Role guard**: `/guide`, `/guide/profile` and `/guide/listing…` require
   `role == 'guide'`; travelers are redirected to `/home`. The backend still
   enforces authorization on every guide endpoint (`require_role`), the guard
   is UX only. Public `/guide/:id` profiles stay open to everyone, which is
   why `/guide/profile` is declared *before* `/guide/:id` (GoRouter takes the
   first match). `/host` and everything under it requires `role == 'host'`,
   and neither role may enter the other's workspace.
5. Signed-out-only screens (`/sign-in`, `/sign-up`, `/onboarding`,
   `/forgot-password`) resolve to `/home` once authenticated;
   `/profile/edit` and `/settings/password` need a session.

Five-tab `StatefulShellRoute` (Home · Explore · Trips · Inbox · Profile) plus
full-screen routes: experience detail, guide profile, destination, booking
flow, Maila Dai, saved, password reset (`/forgot-password`), change password
(`/settings/password`), the guide workspace with its profile editor
(`/guide/profile`), update composer (`/guide/status/new`) and listing editor
(`/guide/listing/new`, `/guide/listing/:id`) — guarded like `/guide` — and the
host workspace with its experience and tour editors.

## Host workspace

`/host` is a three-tab console (Experiences · Tours · Bookings) over the
`/host/*` family, which the server confines to `role == 'host'` and to the
caller's own rows. `PATCH /host/experiences/{id}` and `PATCH /host/tours/{id}`
take the full create body, so both editors always submit every field. A record
id that is not in the host's own list renders "no longer available" rather
than an empty create form. `HostBooking` reuses the shared `BookingStatus`
vocabulary and status chip; only an `upcoming` request offers accept/decline
because the endpoint accepts exactly those two decisions.

## Guide workspace

`/guide` is a four-tab dashboard (Overview · Requests · Listings · Updates).
The Overview opens with a profile card driven by `guideOnboardingProvider`: it
prompts while `onboarding_completed` is missing *or* the details a complete
profile needs (name, expertise, city, language, bio) are gone, and shows the
summary once both hold.

The Updates tab lists `GET /guide/status` (type chip, message, resolved
listing title, capacity and a relative age) and deletes rows with
confirmation; the composer at `/guide/status/new` posts one update, showing
capacity fields only for `capacity` and the date only for `schedule`. All
three editors (profile, listing, update) push on the root navigator and pop
`true` only when the server state changed, so their callers refetch instead
of always reloading.

## Data flow (example: booking)

```
BookingFlow → availability GET /bookings/availability?date=…
           → POST /bookings/ (single non-idempotent call,
             guarded by _submitting/_submitted flags — no auto-retry)
           → invalidate bookingsProvider → Trips shows server truth
```

## Error model

`ApiException` with `ApiFailureKind` (network, unauthorized, forbidden,
notFound, validation, server, canceled, unknown). `ApiClient.mapDioException`
maps every Dio failure once; UI switches on `kind` and shows friendly copy —
backend traces are never rendered.

## Offline / resilience

- Loading → skeleton, never a bare spinner or blank screen.
- Every list has empty + error + retry states.
- Search is debounced (350 ms) and in-flight requests are canceled on filter
  change, so rapid typing can't race stale responses.
- Session restore falls back to the cached identity on network failure
  instead of logging the user out spuriously; a real 401 clears storage and
  ends the session everywhere (`AuthInterceptor.onUnauthorized`).
