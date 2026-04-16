# Testing guide

This file is for the frontend dev (you) plus a local backend
and the Stripe CLI. It assumes you already have the backend
running locally and the web app's API client pointed at it.

## Pointing the frontend at a local backend

Set `API_BASE_URL` (or whatever env var the web app uses) to
`http://localhost:8000` in the frontend dev config and restart
the dev server. The `return_url` and `refresh_url` in the
backend's `.env` should point back at the frontend dev server:

```
STRIPE_CONNECT_RETURN_URL=http://localhost:3000/gym-setup/return
STRIPE_CONNECT_REFRESH_URL=http://localhost:3000/gym-setup/refresh
```

Both routes must exist on the frontend. They can be as simple
as a component that fetches `GET /api/v1/gyms/me/onboarding`
once and then renders `OnboardingPending` with the poller
running.

## Running the backend with Stripe test mode

From the backend repo, with a `.env` that has a Stripe test
secret key (`sk_test_...`):

```bash
cd FastApiBackend
poetry run uvicorn src.main:app --reload --host 0.0.0.0 --port 8000
```

## Forwarding Stripe Connect webhooks locally

Stripe has two webhook categories: account events (for your
platform) and Connect events (for connected accounts). Account
creation / update fires as a Connect event, so use:

```bash
stripe listen \
  --forward-connect-to http://localhost:8000/api/v1/stripe/webhooks
```

`stripe listen` prints a webhook secret like `whsec_...` on
startup — set it as `STRIPE_WEBHOOK_SECRET` in the backend's
`.env` (it may already be set for the non-connect listener too,
in which case the same value works for both).

Keep this running in a separate terminal for the whole test
session. Every `account.updated` event fired by Stripe —
including the one that flips your test account to `complete` —
will be forwarded to the local backend and written to the DB.

## Walking through Express onboarding in test mode

Stripe provides a "use test data" checkbox on the hosted flow
in test mode. It auto-fills:

- **Individual name / DOB / SSN**: test persona
- **Address**: Stripe's test address
- **Phone**: Stripe test number
- **Bank account**: routing `110000000`, account `000123456789`

A walkthrough of the whole flow in test mode takes about 60
seconds of clicking through. At the end Stripe redirects you
to whatever `return_url` the backend was configured with (e.g.
`http://localhost:3000/gym-setup/return`).

If you want to test the return/refresh routes without walking
through Stripe every time, just navigate to them directly in
the browser (`http://localhost:3000/gym-setup/return`) while a
pending gym exists. The route fetches `GET /me/onboarding` and
starts the poller — that's the same behavior as arriving via a
Stripe redirect.

Note that you cannot fake a `complete` Stripe account by just
hitting the return route — the backend will call
`stripe.Account.retrieve` on the real test account, which is
still `pending` until you actually completed the hosted flow.

## Forcing a `disabled` state for UI testing

In Stripe test mode, there is no dashboard button that says
"disable this account". The cleanest way is to trigger a
rejection via the Stripe CLI:

```bash
stripe accounts reject <acct_XXX> --reason fraud
```

This flips `requirements.disabled_reason` to
`"rejected.fraud"` and fires an `account.updated` webhook
which the backend handler will write as `disabled`. The next
poller tick on `GET /api/v1/gyms/me/onboarding` returns
`disabled` with `disabled_reason="rejected.fraud"`, and the
frontend should route to its `Disabled` screen.

Other valid reject reasons: `terms_of_service`, `other`.

## Manual regression checklist

Run through these before shipping any change to the gym setup
flow. Each item is one end-to-end scenario.

- [ ] **Fresh user, happy path** — sign up a new Supabase
      user, run the wizard, complete Stripe onboarding in test
      mode, land on home. Verify:
      - Poller shows `pending` → `complete` within ~10s of the
        Stripe return
      - `gyms_unfiltered` row has `stripe_account_id` set and
        `stripe_onboarding_status = 'complete'`
      - `gym_employees` row exists with `employee_type = 'owner'`
- [ ] **Fresh user, close tab mid-onboarding** — start the
      wizard, `POST /api/v1/gyms/`, click through to Stripe,
      close the tab without completing. Reload the app. Verify:
      - Home bootstrap calls `GET /me/onboarding`
      - UI lands on `ResumeSetup` with a fresh `onboarding_url`
      - "Continue setup" re-fetches if the URL is within 10s of
        expiry and otherwise reuses it directly
- [ ] **Fresh user, let the link expire** — start the wizard
      through `POST /api/v1/gyms/`, wait 6 minutes without
      clicking through. Click through. Stripe redirects to
      `/gym-setup/refresh`. Verify:
      - The refresh route calls `GET /me/onboarding`
      - A new `onboarding_url` is returned and the user is
        navigated to it
- [ ] **Returning user with `complete` gym** — log in as a
      user who already completed setup. Home bootstrap should
      call `GET /me/onboarding`, get `complete`, and skip the
      wizard entirely.
- [ ] **`POST /api/v1/gyms/` twice** — finish setup, then
      re-submit the wizard from a debug path. Verify:
      - Backend returns `409 Conflict` with
        `detail = "Gym already set up"`
      - UI navigates straight to home, not the error screen
- [ ] **`pending` user, re-submit wizard** — start a gym, do
      not finish, then re-submit the wizard from a debug path.
      Verify the backend returns `409` with `detail` starting
      `"Finish onboarding..."` and the UI routes back through
      the resume flow.
- [ ] **Disabled account** — complete onboarding, then
      `stripe accounts reject <acct_XXX>`. Wait for the poller
      tick (or trigger one manually). Verify the UI transitions
      to `Disabled` with the correct `disabled_reason`.
- [ ] **Webhook-only status sync** — start a new gym, complete
      onboarding on Stripe, but keep the browser tab hidden.
      The `account.updated` webhook should arrive within a few
      seconds and write the `complete` status to the DB. When
      you tab back, the next (immediate) poll should return
      `complete` — the backend still re-reads Stripe, but the
      DB already had the right state from the webhook.
- [ ] **Page Visibility pause** — in DevTools, throttle to
      "Offline" while the poller is running. Confirm polls
      pause and there's no request storm. Un-throttle and
      confirm the poller resumes.
- [ ] **RLS regression** — from the browser console on a
      logged-in page, try
      `supabase.from('gyms_unfiltered').insert({...})`. Confirm
      it returns an RLS error (proves the old direct-write path
      is truly dead).
- [ ] **RLS read regression** — as a completed gym owner,
      confirm `supabase.from('gyms').select()` still works for
      reading the gym row (the filtered view is still readable
      via RLS, even though writes are revoked).

If any of these fail, do not ship. Each represents a real
failure mode the backend has been designed to handle; a
failure on the frontend side means the contract has drifted.

## Tips for iterating faster

- Keep `stripe listen` running in one terminal and
  `uvicorn --reload` in another; both auto-pick up changes.
- Tail backend logs with `make run` or the usual uvicorn
  invocation — every gym route logs failures with
  `exc_info=True`, so a 502 / 500 will have a full Python
  traceback you can paste into a bug.
- Use the Stripe dashboard → Developers → Webhooks → recent
  deliveries view to confirm the webhook fired. Replay
  individual events from there if you need to test dedupe
  (the handler must no-op on a replayed event because the
  outer dispatcher's `stripe_webhook_events` insert will fail
  the unique constraint).
- `psql` into the local dev DB and run
  `SELECT gym_id, stripe_account_id, stripe_onboarding_status
   FROM gyms_unfiltered ORDER BY created_at DESC LIMIT 5;`
  to see the last few created gyms. The view `gyms` hides
  rows with a NULL `stripe_account_id`, so always use
  `gyms_unfiltered` for debugging.
