# API reference

All three endpoints live under `/api/v1/gyms`, require a valid
Supabase JWT on every request as
`Authorization: Bearer <access_token>`, and return JSON.

The backend decodes the JWT itself to pull `sub` (Supabase user
id) and `email`. Do NOT include either in the request body — the
request schemas do not have those fields.

## Response conventions

- All timestamps are **ISO-8601 UTC**, e.g.
  `"2026-04-14T18:32:11.123456+00:00"`. Parse with
  `new Date(str)` in JS/TS; compare against `Date.now()`.
- `stripe_onboarding_status` is always one of: `"pending"`,
  `"complete"`, `"disabled"`. The app will never see
  `"not_started"` — that value only exists in the database
  before a Stripe account has been attached, and the only
  endpoint that would hit that state (`POST /api/v1/gyms/`)
  always returns `"pending"`.
- `requirements_currently_due` is a (possibly empty) list of
  opaque Stripe strings like `"individual.verification.document"`
  or `"tos_acceptance.date"`. Display them verbatim if you need
  to show them at all; do not try to localize.
- `disabled_reason` is an opaque Stripe string like
  `"requirements.past_due"` or `"rejected.fraud"`. Same
  treatment: display verbatim, no parsing.
- Error responses use the FastAPI default shape:
  `{"detail": "<string>"}`. On `409 Conflict` the `detail`
  string is part of the contract — see "409 detail strings"
  below.

---

## 1. `POST /api/v1/gyms/` — create a gym

Creates a gym row, the owner's `gym_employees` record, mints a
Stripe Express Connect account, and returns a fresh hosted
onboarding URL.

### Request body

```json
{
  "gym_name": "Eastside Muay Thai",
  "owner_first_name": "Jane",
  "owner_last_name": "Rivera"
}
```

**Fields**

| Field              | Type   | Required | Constraints                      |
|--------------------|--------|----------|----------------------------------|
| `gym_name`         | string | yes      | non-empty after strip            |
| `owner_first_name` | string | yes      | non-empty after strip            |
| `owner_last_name`  | string | yes      | non-empty after strip            |

The backend pulls the owner's email from the JWT `email` claim.
It is passed to Stripe so the hosted flow pre-fills it.

### Success response — `201 Created`

```json
{
  "gym_id": "3f2e2c92-2a1f-4f7a-9c3d-1dc7c8e3c6f1",
  "stripe_account_id": "acct_1PqQZABCDE",
  "stripe_onboarding_status": "pending",
  "onboarding_url": "https://connect.stripe.com/setup/e/acct_1Pq.../abc123",
  "onboarding_url_expires_at": "2026-04-14T18:37:11.123456+00:00"
}
```

`stripe_onboarding_status` is the literal string `"pending"` on
success — there is no intermediate state in which a gym is
created but already-complete. The user always goes through the
hosted flow after this endpoint.

### Status codes

| Code | Meaning                                                      | What the frontend does                                       |
|------|--------------------------------------------------------------|--------------------------------------------------------------|
| 201  | Gym + Stripe account created, onboarding pending             | Navigate to the onboarding URL, start the poller             |
| 400  | Invalid request data (empty field, missing JWT email claim)  | Show a validation error on the form                          |
| 401  | Not authenticated                                            | Bounce to login                                              |
| 409  | User already owns a gym — switch on `detail` (see below)     | Route to home / resume / support depending on detail         |
| 502  | Stripe error                                                 | Show "Stripe is unavailable, try again" with a retry button  |
| 500  | Internal error                                               | Show generic error, retry                                    |

### 409 detail strings

These are part of the contract. Switch on them exactly:

| Detail                                                   | Meaning                                     | UX action                                                       |
|----------------------------------------------------------|---------------------------------------------|-----------------------------------------------------------------|
| `"Gym already set up"`                                   | Gym is `complete`                           | Navigate straight to the home screen                            |
| `"Finish onboarding: GET /api/v1/gyms/me/onboarding"`    | Gym is `pending`                            | Navigate to a "resume setup" screen, call `GET /me/onboarding`  |
| `"Gym Stripe account is disabled, contact support"`      | Gym is `disabled`                           | Navigate to a terminal error screen                             |

If you see a 409 whose `detail` does not match one of the three
above, treat it as an unknown conflict — show a generic error
and bail to the home screen.

### cURL

```bash
curl -X POST 'http://localhost:8000/api/v1/gyms/' \
  -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiI...' \
  -H 'Content-Type: application/json' \
  -d '{
    "gym_name": "Eastside Muay Thai",
    "owner_first_name": "Jane",
    "owner_last_name": "Rivera"
  }'
```

---

## 2. `GET /api/v1/gyms/me/onboarding` — refresh status

Looks up the caller's owned gym (via the bootstrap
`gym_employees` row), asks Stripe for the current account state,
maps it to `pending` / `complete` / `disabled`, writes the new
status to the database if it changed, and — if still `pending` —
mints a fresh AccountLink so the client can re-open the hosted
flow.

### Request body

None. Auth via JWT only.

### Success response — `200 OK`

```json
{
  "gym_id": "3f2e2c92-2a1f-4f7a-9c3d-1dc7c8e3c6f1",
  "stripe_onboarding_status": "pending",
  "onboarding_url": "https://connect.stripe.com/setup/e/acct_1Pq.../xyz789",
  "onboarding_url_expires_at": "2026-04-14T18:37:11.123456+00:00",
  "details_submitted": false,
  "charges_enabled": false,
  "payouts_enabled": false,
  "disabled_reason": null,
  "requirements_currently_due": [
    "individual.verification.document",
    "tos_acceptance.date"
  ]
}
```

**Key fields**

- `stripe_onboarding_status`: `"pending" | "complete" | "disabled"`.
- `onboarding_url`: **non-null only when status is `"pending"`.**
  On `complete` and `disabled` it is `null`.
- `onboarding_url_expires_at`: **non-null only when status is
  `"pending"`.**
- `details_submitted`, `charges_enabled`, `payouts_enabled`:
  raw Stripe flags. Only trust them for optional display; the
  authoritative decision is `stripe_onboarding_status`.
- `disabled_reason`: opaque Stripe string, `null` unless status
  is `"disabled"`. Pass through verbatim.
- `requirements_currently_due`: opaque Stripe strings. Usually
  empty unless status is `"pending"` or `"disabled"`.

### Status codes

| Code | Meaning                                             | What the frontend does                                         |
|------|-----------------------------------------------------|-----------------------------------------------------------------|
| 200  | Status refreshed                                    | Update UI based on `stripe_onboarding_status` (see `04_ui_flow.md`) |
| 401  | Not authenticated                                   | Bounce to login                                                 |
| 404  | No gym owned by this user, or Stripe account missing| Route back to the "create gym" wizard                           |
| 502  | Stripe error                                        | Pause polling briefly; "Stripe is unavailable" with retry       |
| 500  | Internal error                                      | Pause polling briefly; generic error                            |

A 404 here can mean one of two things, both of which route to
the same place (the create wizard):
- The user has no `gym_employees` row as an owner.
- The user has a gym row but its `stripe_account_id` has been
  cleared (the backend does this on read-side 404 from Stripe
  — meaning the Stripe account was deleted out from under us,
  and the user needs to recreate the gym from scratch).

### cURL

```bash
curl -X GET 'http://localhost:8000/api/v1/gyms/me/onboarding' \
  -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiI...'
```

---

## 3. `POST /api/v1/gyms/me/onboarding/link` — fresh hosted URL

The cheap path: mint a new AccountLink without re-reading the
Stripe account. Use this when you already know the gym is in
`pending` state and you just need a new URL — for example, the
user clicked a "get a new Stripe link" button after the previous
one expired. In a polling model this endpoint is mostly
redundant with `GET /me/onboarding` (which also returns a fresh
URL when status is `pending`), but it is cheaper: it skips the
`stripe.Account.retrieve` call.

### Request body

None. Auth via JWT only.

### Success response — `200 OK`

```json
{
  "gym_id": "3f2e2c92-2a1f-4f7a-9c3d-1dc7c8e3c6f1",
  "onboarding_url": "https://connect.stripe.com/setup/e/acct_1Pq.../def456",
  "onboarding_url_expires_at": "2026-04-14T18:37:11.123456+00:00"
}
```

Both fields are always non-null on success.

### Status codes

| Code | Meaning                                             | What the frontend does                                             |
|------|-----------------------------------------------------|--------------------------------------------------------------------|
| 200  | New onboarding link minted                          | Navigate the user to the new URL                                   |
| 401  | Not authenticated                                   | Bounce to login                                                    |
| 404  | No gym owned by this user                           | Route back to the "create gym" wizard                              |
| 409  | Gym is not in `pending` state                       | Call `GET /me/onboarding` instead to learn the actual state        |
| 502  | Stripe error                                        | "Stripe is unavailable, try again" with a retry button             |
| 500  | Internal error                                      | Generic error, retry                                               |

### cURL

```bash
curl -X POST 'http://localhost:8000/api/v1/gyms/me/onboarding/link' \
  -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiI...'
```

---

## Choosing between the two "get a URL" endpoints

| Situation                                                        | Endpoint                              |
|------------------------------------------------------------------|---------------------------------------|
| The poller's regular tick                                        | `GET /me/onboarding`                  |
| App load, user might have an in-progress gym                     | `GET /me/onboarding`                  |
| Stripe redirected to `return_url` / `refresh_url`                | `GET /me/onboarding`                  |
| User clicked a "retry" button after a pause                      | `GET /me/onboarding`                  |
| You already know status is `pending`, just need a new URL        | `POST /me/onboarding/link`            |

**Rule of thumb:** if you need to know what the status is, call
`GET /me/onboarding`. If you already know the status is
`pending` and just want a fresh URL without paying a Stripe
round-trip, call the link endpoint. In practice the poller just
uses `GET /me/onboarding` for everything.
