# Web integration: gym creation + Stripe Connect Express

You are picking up gym creation on the web frontend. The backend
mediates gym creation through Stripe Connect Express: every path
that creates or progresses a gym must go through the three
backend endpoints in `02_api_reference.md`. Direct writes to
`gyms` / `gym_employees` from the Supabase JS client have been
revoked at the database level and will always fail.

There is **no mobile app** — the frontend is a standard browser
SPA. Progress through Stripe's hosted onboarding flow is tracked
by polling the backend, not by deep links or native callbacks.

## Files

1. **`01_flow_overview.md`** — Narrative: happy path, refresh
   path, kill/resume path, disabled path, with a sequence
   diagram. Read this first.
2. **`02_api_reference.md`** — Exact request/response shapes for
   the three endpoints under `/api/v1/gyms`, plus cURL examples
   and the 409 `detail` strings the client must switch on.
3. **`03_polling.md`** — The polling recipe: cadence, start/stop
   conditions, handling the Stripe return URL, Page Visibility,
   backoff on errors.
4. **`04_ui_flow.md`** — The minimum set of UI screens the
   frontend needs and which responses drive transitions between
   them.
5. **`05_error_handling.md`** — HTTP status → user-facing copy +
   UX action, retry policy, expired-link handling, "what NOT to
   do" list.
6. **`06_testing_guide.md`** — How to run the backend locally,
   forward Stripe Connect webhooks with `stripe listen`, force a
   `disabled` account for UI testing, and the manual regression
   checklist.

## Base URL + auth

All three endpoints live under **`/api/v1/gyms`** on the same
backend host you already hit for `/api/v1/members`,
`/api/v1/classes` etc. Attach the Supabase access token as
`Authorization: Bearer <token>` on every request. The backend
decodes the JWT itself to pull `sub` (Supabase user id) and
`email`; you do **not** send either in request bodies, and the
request schemas do not accept them.

## `return_url` / `refresh_url` config

Stripe requires both URLs when it mints a hosted onboarding
link. The backend stores them as `settings.stripe_connect_return_url`
and `settings.stripe_connect_refresh_url`. Set these to the
frontend routes that should handle each case, e.g.

```
STRIPE_CONNECT_RETURN_URL=https://app.combatden.com/gym-setup/return
STRIPE_CONNECT_REFRESH_URL=https://app.combatden.com/gym-setup/refresh
```

For local dev, point them at your dev server (`http://localhost:3000/...`).
Neither route needs to do anything fancy — they just need to
render a "checking your Stripe setup..." screen. The poller will
observe the actual state transition within ~10s and route
accordingly.

## Non-negotiables

- **The hosted Stripe onboarding URL expires in ~5 minutes.**
  Treat every response that contains one as single-use and
  short-lived. Re-fetch via `GET /me/onboarding` when needed.
- **The gym row is invisible through `supabase.from('gyms')`
  until Stripe onboarding has begun.** Never assume you can
  query it directly during setup. Always go through the backend.
- **Trust the backend's status over any local cache.** Every
  poll response is the source of truth; local state is a
  rendering hint at best.
- **Do not parse `disabled_reason` or `requirements_currently_due`.**
  They are opaque Stripe strings. Display verbatim (if at all)
  and pass through to support.
