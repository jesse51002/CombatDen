# UI flow

The minimum set of screens the frontend needs, and which
backend responses transition between them. Framework-agnostic —
translate to whatever state container you use (Zustand, Redux,
React Query + local state, plain `useState`, etc.).

## Screens

| Screen              | When                                                           | Key data held                                |
|---------------------|----------------------------------------------------------------|----------------------------------------------|
| `CheckingGym`       | App load, before the bootstrap status check has returned      | —                                            |
| `Welcome`           | Bootstrap returned 404 (no gym yet)                            | —                                            |
| `WizardForm`        | User is filling out gym name / owner name                      | form draft                                   |
| `SubmittingCreate`  | `POST /api/v1/gyms/` in flight                                 | form values                                  |
| `OnboardingPending` | Gym is `pending`; poller is running; user is on Stripe or en route | `gymId`, `onboardingUrl`, `expiresAt`    |
| `ResumeSetup`       | Bootstrap returned `pending` on app load                       | `gymId`, `onboardingUrl`, `expiresAt`        |
| `Complete`          | Poller saw `status=complete`                                   | `gymId`                                      |
| `Disabled`          | Poller saw `status=disabled`                                   | `gymId`, `disabledReason`                    |
| `ErrorRecoverable`  | 500/502/network error with a retry action                      | last attempted operation                     |

`Complete` and `Disabled` are terminal from the gym-setup flow's
point of view. `Complete` immediately navigates to the home
screen; `Disabled` stays put and shows a "contact support"
message with the opaque `disabled_reason` passed through.

## Transitions

### Bootstrap (home screen on app load)

Always call `GET /api/v1/gyms/me/onboarding` before rendering
any gym-dependent content. Do not cache status across app
sessions.

| Response                    | Destination                                       |
|-----------------------------|---------------------------------------------------|
| 200, `status=complete`      | home screen (skip gym setup entirely)             |
| 200, `status=pending`       | `ResumeSetup`                                     |
| 200, `status=disabled`      | `Disabled`                                        |
| 404                         | `Welcome`                                         |
| 5xx / network               | `ErrorRecoverable` (retry → bootstrap again)      |

### Wizard → create

```
Welcome
  user clicks "Set up your gym"
  → WizardForm

WizardForm
  user submits {gym_name, owner_first_name, owner_last_name}
  → SubmittingCreate
  side effect: POST /api/v1/gyms/

SubmittingCreate
  201 { gym_id, onboarding_url, expires_at, status=pending }
    → OnboardingPending(...)
    side effect: navigate to onboarding_url, start poller
  409 detail="Gym already set up"
    → home screen
  409 detail starts with "Finish onboarding"
    → refetch GET /me/onboarding, route based on new status
  409 detail="Gym Stripe account is disabled, contact support"
    → Disabled (disabledReason unknown until refetch — optional)
  400 / 401 / 5xx / network
    → ErrorRecoverable (retry goes back to SubmittingCreate)
```

### OnboardingPending (poller running)

`OnboardingPending` is the state the user spends most of their
setup time in. The poller runs continuously (respecting Page
Visibility — see `03_polling.md`). Every poll tick is a
`GET /me/onboarding` whose response drives transitions:

| Poll response               | Destination                                           |
|-----------------------------|-------------------------------------------------------|
| 200, `status=pending`       | stay in `OnboardingPending` (update cached URL + expiresAt) |
| 200, `status=complete`      | `Complete` → navigate home                            |
| 200, `status=disabled`      | `Disabled` (carry `disabled_reason`)                  |
| 404                         | `Welcome` (gym vanished — backend cleared linkage)    |
| 5xx / network               | show subtle "trouble reaching backend" banner, keep polling with backoff |

### ResumeSetup (bootstrap found pending)

```
ResumeSetup(gymId, onboardingUrl, expiresAt)
  user clicks "Continue setup"
    if expiresAt is within 10s of now:
      refetch GET /me/onboarding first → use fresh URL
    navigate to onboardingUrl
    → OnboardingPending(...)
    side effect: start poller
  user clicks "Start over" (optional)
    → Welcome
    (the backend has no "delete my pending gym" endpoint;
     next POST will 409 with "Finish onboarding" and the app
     will route back through the normal resume path)
```

### Stripe return / refresh routes

The frontend's `/gym-setup/return` and `/gym-setup/refresh`
routes are both rendered as a thin "verifying your Stripe
setup..." screen that:

1. Calls `GET /me/onboarding` once immediately.
2. Transitions into `OnboardingPending` with the poller
   running, or `Complete` / `Disabled` directly if the first
   fetch already reveals that state.

You do not need separate logic for return vs refresh in a
polling model — both routes do the same thing. (Stripe itself
picks which one to redirect to; the UX difference is that
`refresh` means "you'll need to open Stripe again", while
`return` usually means "you're done".)

### Error recovery

`ErrorRecoverable` carries the last operation that failed, so
the retry button can replay it:

- Failed bootstrap → retry bootstrap
- Failed create → retry create with the form values
- Failed poll tick → just wait for the next tick (the poller
  handles retries itself)

## Back navigation and cancels

- From `WizardForm`, back goes to `Welcome`.
- From `OnboardingPending` or `ResumeSetup`, "cancel" is a
  soft exit: the gym row still exists in the database as
  `pending`. Next time the user opens the app, the bootstrap
  check will find it and route them back to `ResumeSetup`.
  There is no "delete my pending gym" endpoint by design —
  gym creation is a one-shot, audit-worthy operation.
- From `Disabled` or `Complete`, there is no back navigation
  within gym-setup; those are terminal.

## Do-not

- **Do not** cache `stripe_onboarding_status` in
  `localStorage` / `sessionStorage` across app sessions. The
  DB can change under you at any moment via webhook. Re-fetch
  on every app load.
- **Do not** show a modal / full-screen blocker while polling.
  The user may want to close the Stripe tab, come back, and
  see a normal status screen — not a dialog they can't
  dismiss.
- **Do not** assume the first poll after a Stripe return will
  be `complete`. There is a small window where Stripe has
  redirected the user but the backend's next
  `accounts.retrieve` still shows `charges_enabled=false`. The
  poller will catch up within 1-2 ticks.
