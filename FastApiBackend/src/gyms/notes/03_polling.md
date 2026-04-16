# Polling

The frontend detects Stripe onboarding progress by polling
`GET /api/v1/gyms/me/onboarding` at a fixed cadence while the
user is mid-setup. There is no push from the backend to the
browser — the `account.updated` webhook from Stripe is consumed
server-side to keep the DB fresh, and the poller is how the
frontend sees that freshness.

## Cadence

**10 seconds between polls** while the user is on a gym-setup
screen. That's a reasonable compromise between:
- Latency the user perceives after they finish Stripe's hosted
  flow (worst case: 10s of staring at a spinner after Stripe
  redirects them back).
- Load on the backend, which calls `stripe.Account.retrieve` on
  every poll.

Do not use an exponential backoff for successful polls — the
user expects near-real-time feedback when they've just finished
hosted onboarding. Do apply backoff on errors (see below).

## When to start polling

Start the poller on any screen where the UI depends on the
current gym status:

- Immediately after a successful `POST /api/v1/gyms/` response
  (`status=pending`) — the user has been navigated to (or is
  about to be navigated to) the Stripe hosted URL.
- On the `/gym-setup/return` route (where Stripe redirects on
  success) — even if the first fetch already shows `complete`,
  keep the poller running for a few ticks as a safety margin
  against a race between the Stripe hosted flow's final POST
  and Stripe's own `account.updated` webhook landing in our DB.
- On the `/gym-setup/refresh` route — after refetching status
  you will immediately navigate the user to a new hosted URL,
  and the poller continues running from wherever it was.
- On a "resume setup" screen reached from a kill/relaunch check
  that returned `pending`.

## When to stop polling

- `status == "complete"` — navigate home; no more polling.
- `status == "disabled"` — route to terminal error screen; no
  more polling.
- 404 — the gym is gone; route to the create wizard; no more
  polling.
- The user navigates away from every gym-setup screen.
- **The tab is hidden for more than ~60 seconds** (see "Page
  Visibility" below).

## Page Visibility — don't poll a hidden tab

Browsers throttle setTimeout/setInterval when a tab is backgrounded
anyway, but the explicit rule is simpler and avoids surprises:

1. When `document.visibilityState === "hidden"`, pause the
   poller.
2. When the tab becomes `visible` again, fire an immediate
   `GET /me/onboarding` (not a 10s wait) and then resume the
   10-second cadence.

This matters because the user probably opened Stripe in a new
tab and switched to it. The "main" tab sits hidden while they
fill out the hosted form. When they tab back, they want an
immediate answer, not a 10-second wait.

A minimal skeleton:

```ts
function startPolling(onState: (r: OnboardingResponse) => void) {
  let timer: number | null = null;
  let cancelled = false;

  async function tick() {
    if (cancelled || document.visibilityState === "hidden") return;
    try {
      const res = await apiGet<OnboardingResponse>("/api/v1/gyms/me/onboarding");
      onState(res);
      if (res.stripe_onboarding_status !== "pending") return; // stop
      timer = window.setTimeout(tick, 10_000);
    } catch (err) {
      // see "Errors + backoff" below
      timer = window.setTimeout(tick, 15_000);
    }
  }

  function onVisibility() {
    if (document.visibilityState === "visible") {
      if (timer) window.clearTimeout(timer);
      tick();
    }
  }

  document.addEventListener("visibilitychange", onVisibility);
  tick();

  return () => {
    cancelled = true;
    if (timer) window.clearTimeout(timer);
    document.removeEventListener("visibilitychange", onVisibility);
  };
}
```

## Errors + backoff

On a poll failure, **do not stop polling** — the user is still
mid-setup and needs the eventual answer. But do back off so you
don't hammer a struggling backend.

| Response                        | Action                                                     |
|---------------------------------|------------------------------------------------------------|
| 200                             | Normal 10s tick                                            |
| 401                             | Stop poller, bounce to login                               |
| 404                             | Stop poller, route to create wizard                        |
| 409 (on the link endpoint only) | Refetch `GET /me/onboarding` to learn actual state         |
| 5xx / network                   | Next tick after 15s, then 30s, then 60s (cap); reset on 200|

Show a subtle "having trouble reaching the backend" banner when
the poller has had two consecutive errors. Clear it on the next
successful 200.

## Opening the Stripe hosted URL

Two reasonable patterns — pick one and stick with it:

### Pattern A: full-page redirect

```ts
window.location.href = response.onboarding_url;
```

When Stripe finishes, it redirects to `return_url`
(`/gym-setup/return`) or `refresh_url` (`/gym-setup/refresh`).
Both are frontend routes that render a "verifying..." screen
and start the poller. The user's attention never leaves the
browser tab; they just see one screen replaced by another.

Pro: simplest to reason about. The poller only runs on the
return/refresh routes, never in parallel with Stripe.

Con: if the user hits back during the hosted flow, they're
stuck navigating backward through Stripe. Most users don't.

### Pattern B: new tab + main-tab poller

```ts
window.open(response.onboarding_url, "_blank", "noopener");
// Stay on "finishing setup..." page; poller was already started.
```

The main tab shows a "finishing your Stripe setup..." status
page with the poller running the whole time. The new tab has
the hosted flow. When the user finishes in the new tab, Stripe's
redirect lands in that tab; the main-tab poller sees the
`complete` status within 10s and navigates home. The user can
close the now-redundant Stripe tab.

Pro: main tab is always ready to show the final state.

Con: two tabs means two things for the user to keep track of.
Also, popup blockers may bite you if `window.open` isn't
triggered directly by a user gesture.

### Which to pick

Pattern A is simpler to implement and debug; start with it. Move
to Pattern B only if you want the "status + Stripe side-by-side"
UX.

## Expired URLs

Every poll response in `pending` state comes with a fresh
`onboarding_url` + `onboarding_url_expires_at`. Treat the URL as
**single-use**: once the user has clicked or been redirected to
it, assume it's consumed. If you need to send them back to
Stripe (e.g., they closed the tab and came back to the main
tab), re-fetch via another `GET /me/onboarding` call to get a
fresh URL rather than reusing the cached one.

Before navigating, verify:

```ts
const expiresAt = new Date(response.onboarding_url_expires_at);
if (expiresAt.getTime() - Date.now() < 10_000) {
  // less than 10s of life left; re-fetch first
  const fresh = await apiGet<OnboardingResponse>(
    "/api/v1/gyms/me/onboarding"
  );
  // use fresh.onboarding_url
}
```

The 10-second safety margin avoids the race where the URL is
"valid" at check time but expires in the network trip to Stripe.
