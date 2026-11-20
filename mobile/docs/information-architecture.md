# Information Architecture

Ground truth: [`lib/app/router/app_router.dart`](../lib/app/router/app_router.dart)
(routes + `authRedirect`), [`lib/app/app_shell.dart`](../lib/app/app_shell.dart)
(tabs) and `lib/features/**` (screens). This document describes what the app
actually does. Anything the app deliberately does **not** do is listed in
[Deliberate exclusions](#deliberate-exclusions) rather than implied to exist.

## 1. Navigation model

Two surfaces, one guard:

```
                        ┌─────────────┐
                        │   /splash   │  session restore against GET /profile/me
                        └──────┬──────┘
              signed out       │        signed in
                 ┌─────────────┴──────────────┐
                 ▼                            ▼
        ┌──────────────────┐        ┌──────────────────────────┐
        │  /onboarding     │        │  five-tab shell (pushed   │
        │  /sign-in        │        │  over by detail routes)   │
        │  /sign-up        │        └────────────┬─────────────┘
        │  /faq /contact   │                     │
        └──────────────────┘        Home · Explore · Trips · Inbox · Profile
```

- **Shell tabs** are a `StatefulShellRoute.indexedStack`, so each tab keeps its
  own scroll position and stack. They are the five destinations a traveler
  lives in.
- **Everything else is a root-navigator route** pushed *over* the shell, so a
  detail page owns the full screen and can be deep-linked by path.
- The tab bar is a floating rounded panel (`FloatingNavBar`, 68 dp) and content scrolls
  beneath it (`extendBody: true`); every screen pads its own `SafeArea`.
- The Inbox tab carries the unread badge, fed by the same fetch that renders
  the Inbox list, and refreshes when the tab is entered.

### Route table

| Path | Screen | Navigator |
|---|---|---|
| `/splash` | `SplashScreen` | root |
| `/onboarding` | `OnboardingScreen` | root |
| `/sign-in`, `/sign-up` | `SignInScreen`, `SignUpScreen` | root |
| `/home` | `HomeShell` (tab 0) | shell |
| `/explore` | `ExploreScreen` (tab 1) | shell |
| `/trips` | `TripsScreen` (tab 2) | shell |
| `/inbox` | `InboxScreen` (tab 3) | shell |
| `/profile` | `ProfileScreen` (tab 4) | shell |
| `/profile/edit` | `ProfileEditScreen` (signed-in only) | root |
| `/experience/:slug` | `ExperienceDetailScreen` | root |
| `/book/:slug` | `BookingFlow` | root |
| `/destination/:city` | `DestinationScreen` | root |
| `/guide/:id` | `GuideProfileScreen` (public) | root |
| `/inbox/:id` | `ConversationScreen` | root |
| `/ai` | `AiAssistantScreen` | root |
| `/saved` | `SavedScreen` | root |
| `/faq`, `/contact` | `FaqScreen`, `ContactScreen` (public) | root |
| `/guide` | `GuideShell` (role-guarded) | root |
| `/guide/profile` | `GuideProfileEditorScreen` (guarded) | root |
| `/guide/listing/new`, `/guide/listing/:id` | `ListingEditorScreen` (guarded) | root |
| `/guide/status/new` | `GuideStatusComposerScreen` (guarded) | root |

**Route ordering is load-bearing:** `/guide/profile` is declared *before*
`/guide/:id` because GoRouter takes the first match — otherwise the guide's
own editor would resolve to a public profile page.

## 2. Access rules (`authRedirect`)

| Session state | Reachable | Anything else resolves to |
|---|---|---|
| restoring | `/splash` | `/splash` |
| signed out | `/onboarding`, `/sign-in`, `/sign-up`, `/faq`, `/contact` | `/sign-in` |
| signed in | everything except the signed-out set | `/sign-in`/`/sign-up`/`/onboarding`/`/splash` → `/home` |
| signed in, not a guide | everything public | `/guide`, `/guide/profile`, `/guide/listing*`, `/guide/status*` → `/home` |
| signed in, not a host | everything public | `/host`, `/host/experience*`, `/host/tour*` → `/home` |
| signed out | `/profile` shows a sign-in prompt | `/profile/edit`, `/settings/password` → `/sign-in` |

Both role guards are **UX only**. Every `/guide/*` endpoint is additionally
`require_role("guide")` and every `/host/*` endpoint `current_host` (role
`host`) on the server, each scoped to the caller, so a tampered client gains
nothing. `admin`, `content-manager`, `regional-head` and `customer-support`
are *not* given mobile consoles: staff work stays in the web dashboard, which
is the authoritative interface for it.

`guide` and `host` are different roles owning different records, so they get
different workspaces and neither can enter the other's.

## 2b. Host workspace

```
Profile ─► Host tools ─► /host ─┬─► Experiences ─► create / edit / delete
                                ├─► Tours       ─► create / edit / delete
                                └─► Bookings    ─► accept / decline
```

| Step | Screen | Server truth |
|---|---|---|
| Overview | Experiences tab: owned experiences, live/inactive chip, per-person price | `GET /host/experiences` |
| Manage | Experience editor (whole-body save) | `POST /host/experiences`, `PATCH /host/experiences/{id}`, `DELETE /host/experiences/{id}` |
| Tours | Tours tab + tour editor | `GET|POST /host/tours`, `PATCH|DELETE /host/tours/{id}` |
| Decide | Bookings tab: guest, contact, date, guests, total, notes, accept/decline | `GET /host/bookings`, `PATCH /host/bookings/{id}` |

Not surfaced because the API does not offer it: host earnings and performance
metrics, `POST /host/bookings` (a host typing in an off-platform booking),
marking a booking `completed` (`PATCH` accepts only `accepted`/`rejected`) and
toggling `is_active` on a host experience/ tour (reported, never offered as a
switch). See [api-gaps.md](api-gaps.md).

## 3. Traveler journey

```
Onboarding ─► Sign in ─► Home ─┬─► Search (Explore) ─► Experience ─┬─► Book ─► Trips
                               ├─► Destination ────────────────────┘          │
                               ├─► Guide profile ─► message ─► Inbox ─────────┤
                               ├─► Maila Dai (/ai)                            │
                               └─► Saved (/saved) ◄──────── heart on any card ┘
```

| Step | Screen | Server truth |
|---|---|---|
| Discover | Home: greeting, seasonal hero, city cards, categories, curated experiences, city updates | `GET /experiences`, `GET /guides`, `GET /updates?city=` |
| Browse | Explore: debounced search, city + category chips, results grid | `GET /experiences?search=&city=&category=` |
| Understand | Experience detail: gallery, host, itinerary, reviews, meeting point, price | `GET /experiences/{slug}`, `GET /reviews/?experience_id=` |
| Commit | Booking flow: date → guests → review → submit | `GET /bookings/availability`, `POST /bookings/` |
| Return | Trips: upcoming / past, status chips, cancel, archive, review | `GET /bookings/`, `POST /bookings/{id}/cancel`, `POST /bookings/{id}/archive` |
| Talk | Inbox → conversation | `GET /conversations`, `GET|POST /conversations/{id}/messages` |
| Ask | Maila Dai | `POST /ai/chat` |

Cross-cutting: **saving** is optimistic and reconciles with
`GET|POST|DELETE /profile/bookmarks`; it is rolled back if the server refuses,
so a failed save never looks saved.

## 4. Guide journey

Reached from Profile (`/guide` is only visible to a guide account).

```
/guide  ── Overview ── profile card (onboarding completeness) ──► /guide/profile
   │      Requests ── accept / decline / complete (PATCH /guide/bookings/{id})
   │      Listings ── create / edit / pause / delete ────────────► /guide/listing/{id}
   └────  Updates  ── feed + composer ──────────────────────────► /guide/status/new
```

- The Overview card prompts while `onboarding_completed` is missing **or** the
  fields a complete profile needs (name, expertise, city, language, bio) are
  absent — the server stores the flag without validating the profile, so the
  client refuses to imply "done" when it is not.
- Editors pop `true` only when server state changed; callers refetch instead of
  always reloading.
- A listing the guide does not own loads as "no longer available", never as a
  blank create form.

## 5. Screen inventory & state coverage

Every list-bearing screen ships loading, empty, error and retry states
(`SkeletonList`, `EmptyStateView`, `ErrorStateView`).

| Screen | Primary content | Loading | Empty | Error |
|---|---|---|---|---|
| Home | hero, cities, categories, curated, updates | skeleton | per-section "nothing here yet" | inline retry |
| Explore | search + filters + results | skeleton grid | "no matches, clear filters" | retry with filters kept |
| Destination | city hero, experiences, updates | skeleton | city with no listings | retry |
| Experience detail | gallery, host, reviews, price | skeleton | n/a (404 → not found) | error + back |
| Booking flow | date, guests, summary | inline (availability) | sold-out day explained | submit error, form intact |
| Trips | bookings by state | skeleton | "no trips yet" → Explore | retry |
| Inbox | threads + unread | skeleton | "no messages yet" | retry |
| Conversation | message list + composer | skeleton | thread start copy | send-failed row + retry |
| Saved | bookmarks | skeleton | "nothing saved" | retry |
| Profile | identity, actions, guide entry | skeleton | n/a | retry |
| Edit profile | name, photo, phone, bio | inline photo preview | n/a | field + banner errors, form kept |
| Maila Dai | chat transcript | typing indicator | suggested prompts | retry / stop |
| Guide workspace | stats, requests, listings, updates | skeleton | per-tab empty copy | retry |
| Auth screens | fields, submit | button loading blocks double submit | n/a | field + banner errors |
| FAQ / Contact | static + form | n/a | n/a | submit error |

## 6. Feedback & interaction rules

- **Search** debounces 350 ms and cancels the in-flight request when filters
  change, so a slow response can never overwrite a newer query.
- **Booking** is a single non-idempotent `POST` guarded by submit flags. It is
  never auto-retried; a retry is a deliberate user action.
- **Destructive actions** (cancel booking, delete listing, delete update, sign
  out of all devices) always confirm first.
- **Errors** are mapped once in `ApiClient.mapDioException` to `ApiFailureKind`
  and rendered as friendly copy — never a stack trace, token or server detail.
- **Session expiry** ends the session everywhere via the auth interceptor;
  the user lands on sign-in rather than a half-populated screen.
- **Reduced motion** (`MediaQuery.disableAnimationsOf`) disables shimmer and
  transitions.

## 7. Content, locale and money

- All copy lives in `AppStrings` — no literal UI strings in widgets.
- Dates and money are formatted centrally (`formatters.dart`); prices use the
  server's value and are never converted with invented rates.
- Nepal time (UTC+05:45) is used for "today"-style labels and guide updates,
  matching the server's own day boundary.

## 8. Deliberate exclusions

| Not in the app | Why | What it would need |
|---|---|---|
| Host earnings & performance | No `/host/*` endpoint returns them | Metrics endpoints (and a payout model) |
| Staff consoles (admin, content-manager, regional-head, support) | The web dashboard is the authoritative tool | Nothing — declining is the decision |
| Payments | `POST /bookings/` creates an `upcoming` booking with no charge | Provider choice, server-side verification, webhooks |
| Time-slot picker | Availability is day-level | Per-slot endpoint + `time` on `BookingCreate` |
| OAuth buttons | OAuth redirects to the website with tokens in the query string | PKCE + deep-link callback |
| Maps | Adds a paid SDK and key management for little planning value today | Provider decision + key restrictions |
| Push notifications | No device-token endpoints exist | Token registration + delivery pipeline |
| Personalized custom offers | No persistence model for offers | Offer model, endpoints, transitions |

These are recorded with evidence in [api-gaps.md](api-gaps.md).

## 9. Reference viewports

Designed for 360×800 → 430×932 logical pixels (the phone range), verified at
390×844. Layouts are single-column, scroll-first, with no fixed heights around
text so system font scaling reflows instead of clipping.
