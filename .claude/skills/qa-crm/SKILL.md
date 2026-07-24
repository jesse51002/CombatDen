---
name: qa-crm
description: >-
  Drive the live CRM admin web app in a headless browser and prove every page
  works — boot a debug build with dev auto-login, deep-link each page by URL,
  screenshot it, and confirm it renders with no Flutter exceptions and clean
  backend calls. Use whenever the user wants to "QA the pages", "make sure the
  pages work", "smoke test the CRM", "screenshot every screen", "check the app
  visually", "test the Flutter pages", or after a change that could affect
  routing, auth, the members list, member detail, or Kiosk Mode (check-in +
  self-serve signup). Catches render crashes, stuck spinners, stale-build
  regressions, and broken backend wiring that `flutter analyze` can't see.
---

# QA the CRM pages (browser pass)

The job: open the **real** running app, visit **every** admin page, and confirm
each one renders against the live backend. `flutter analyze` being clean does
not mean a page renders — layout crashes, pagination loops, empty-`gym_id`
422s, and stale builds all pass analysis and fail in the browser. This skill is
how you catch them.

Underlying tool: the **gstack `browse`** skill (headless Chromium). Alias it
once per session: `B=~/.claude/skills/gstack/browse/dist/browse`. Core verbs:
`$B goto <url>`, `$B wait --networkidle --timeout <ms>`, `$B console --errors`,
`$B network`, `$B screenshot <path>`, `$B restart`.

## 1. Bring the stack up

The app talks to four sibling services on localhost. Confirm they're listening
before you start (`ss -ltn | grep -E ':8000|:8001|:8002|:54321'`):

- **FastApiBackend** `:8000` — the CRM backend (members, billing, gyms). Required.
- **ThemeService** `:8001` — theme preview catalog. Required for the Member-App Theme tab.
- **VideoService** `:8002` — read-only video feed + gym detail. Optional; the app degrades quietly without it (see *Edge-data degradations*).
- **Supabase** `:54321` — auth + Postgres (docker `supabase_db_Gymworld`; the
  container name follows the Supabase project, so confirm with
  `docker ps --format '{{.Names}}' | grep supabase_db`).

If a service is down, start it from its own dir (`make run`) — don't fake it.

## 2. Run a DEBUG build with dev auto-login

Two non-negotiables:

- **Debug, not release.** A release build loads `.env.prod` and points at
  `api.combatden.net` — you'll QA prod by accident. `flutter run` (debug) loads
  `.env.dev` → `API_BASE_URL=http://localhost:8000`. Always debug.
- **Dev auto-login puts the token in the session for you.** `LoginBloc` has a
  dev-only auto-login gated by two compile-time defines (empty in prod → normal
  login flow). Pass them and a fresh browser lands authenticated — no clicking
  through the login form:

```bash
# Port MUST be on the backend CORS allowlist (FastApiBackend .env CORS_ORIGINS):
# 8080, 8081, 8082, 3000 — any other port (e.g. 8090) gets the /gyms/ call
# CORS-blocked and the app falls back to the login screen. 8081 = make run and
# 8082 = make run-themes (likely the user's own, possibly-stale servers), so the
# safe free QA port is **8080**. Leave the user's servers alone.
nohup flutter run -d web-server --web-port 8080 \
  --dart-define=DEV_AUTOLOGIN_EMAIL=owner1@test.com \
  --dart-define=DEV_AUTOLOGIN_PASSWORD=abcd1234 \
  > /tmp/crm_qa.log 2>&1 &
```

`owner1@test.com` / `abcd1234` is the seeded gym owner. The seed runs with
`NUM_GYMS=1`, so **only `owner1@test.com` exists** (there is no `owner2…`); it
owns the single seeded gym (whatever name the current seed gives it — query
`select gym_name from gyms;` if you need it). `/members/list` enforces gym
ownership (403 for gyms you don't own), so the auto-login account must own a gym
with seeded data. Confirm the account is valid before blaming the build:
`curl -s -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password"
-H "apikey: $ANON" -d '{"email":"owner1@test.com","password":"abcd1234"}'`
should return an `access_token` (creds in `CRM/.env.dev`).

The port serves `index.html` immediately, but **DDC compiles the whole app on
the first browser connection** — hundreds of `*.dart.lib.js` modules, 60–120s
cold. Poll the log / port, then be patient on first `goto`.

## 3. Deep-link every page (don't click — canvaskit can't be clicked by ARIA)

The app renders to a **canvas** (canvaskit), so there's no DOM to click by
label. Navigate by **URL fragment** instead — every section is deep-linkable
(hash routing; routes in `lib/core/navigation/app_routes.dart`). `main.dart`
always mounts the AuthGate first, so a deep-link still resolves the gym before
the page builds.

| Page | URL |
|------|-----|
| Members list | `http://localhost:8080/#/members` |
| Member detail | `http://localhost:8080/#/members/detail` |
| Member-app preview (Theme tab) | `http://localhost:8080/#/members/app-preview` |
| Member-app Videos / Loyalty tabs | `…/#/members/app-preview/videos` , `…/loyalty` |
| Schedule | `http://localhost:8080/#/schedule` |
| Growth | `http://localhost:8080/#/growth` |
| Employees | `http://localhost:8080/#/employees` |
| QR codes | `http://localhost:8080/#/qr-codes` |
| **Dashboard** | `http://localhost:8080/#/home` |

**Dashboard is the default landing view:** the workspace defaults a bare `/`
(no fragment) → the `HomeScreen` dashboard, so a fresh load lands there. Its
explicit URL is `/#/home`, and an unmatched path also falls back to `HomeScreen`
in `_onGenerateRoute`. The **Members list** is reached via its own `/#/members`.

Per page: `goto`, then `wait --networkidle` (loop a few times on first load
while DDC finishes), then capture:

```bash
$B goto "http://localhost:8080/#/members" 2>&1 | tail -1
for i in $(seq 1 12); do $B wait --networkidle --timeout 8000 >/dev/null 2>&1; done
$B console --errors 2>&1 | tail
$B network 2>&1 | grep -E 'localhost:8000/api' | sed -E 's/ \([0-9]+ms.*//' | sort | uniq -c
$B screenshot "/tmp/crm_qa/members.png"   # screenshots ONLY to /tmp or the repo
```

Then **Read the screenshot** and judge it: real data vs. spinner vs. blank.

## 4. What "passes"

- The page **renders content**, not a spinner or blank canvas.
- **Zero Flutter render exceptions** in `console --errors` (ignore the benign
  ones in *Gotchas*).
- Backend CRM calls return **200**: `GET /gyms/` (the auth gate lists
  administrable gyms), `POST /members/list`, `GET /members/counts`, and
  `GET /members/{id}/billing` on detail. A `4xx`/`5xx` on these is a real
  failure — pull
  the body (`curl` the endpoint with a token from
  `FastApiBackend/scripts/generate_token.py`) to see why.

## 5. Gotchas (every one of these has bitten a real run)

- **Stale build after a dev-server restart.** When you restart `flutter run`,
  the browser keeps serving the **old cached build** (you'll see a refused
  WebSocket to `ws://…/$dwdsSseHandler` and behavior from before your fix). Fix:
  **`$B restart`** for a fresh browser, then re-`goto`.
- **The nohup'd `flutter run` can't take keystrokes**, so you can't hot-reload
  (`r`) or hot-restart (`R`) it. Any code change → kill the process and relaunch.
  `main.dart` changes specifically need a full restart regardless.
- **Always QA the *current* build.** A server started before your fix runs old
  code. Classic symptom: `"Failed to load members list"` repeated — a pre-fix
  build mounts the list before the auth gate resolves the gym, sends an **empty
  `gym_id`**, and the backend returns **422** (`invalid UUID, length 0`). Not a
  backend bug; restart the stale server.
- **Benign console noise** on this Linux/AMD/Mesa box: `WebGL … GPU stall due
  to ReadPixels`, `WEBGL_debug_renderer_info is deprecated`, Stripe
  partitioned-cookie / HTTP-vs-HTTPS warnings, source-map 404s for
  `flutter.js.map`, occasional `CONTEXT_LOST_WEBGL`. None are failures — filter
  them out (but a *persistently* blank canvas after a long settle can be a real
  GPU context loss on this box; re-`$B restart` and reload before concluding).
- **Wrong port → CORS block that looks like an auth failure.** If you launch on a
  port outside the backend's `CORS_ORIGINS` allowlist (8080/8081/8082/3000), the
  Supabase auto-login *succeeds* but `GET :8000/api/v1/gyms/` is blocked
  (`No 'Access-Control-Allow-Origin' header`), gym resolution fails, and you land
  back on the login screen — easy to misread as bad credentials. Use 8080. Check
  `$B console --errors | grep -i cors` when a page won't get past login.
- **You can only reach URL-addressable pages — not dialogs/buttons.** canvaskit
  has no clickable DOM; the `browse` tool's ARIA `click` finds nothing (Flutter
  semantics aren't enabled) and raw coordinate clicks are denied
  (`Input.dispatchMouseEvent` is not on the CDP allowlist). So anything opened by
  tapping a canvas control — **action-row dialogs (Start Membership, Edit, Charge
  Card…), member-row → detail navigation, tab switches** — can't be driven from
  here. Verify those by URL where one exists, or hand them to the user to click
  in a real browser (the auto-login QA server at `:8080` is ready for that).
- **`/#/members/detail` deep-link can render blank cold.** The no-member-id path
  goes through `_FirstMemberResolver`; on a cold load it sometimes never fires a
  `/billing` call and paints blank. Not necessarily a regression — the normal
  path (clicking a member row) takes a real `memberId` and skips the resolver. If
  you only need to confirm the *detail page* renders and the deep-link is blank,
  say so rather than blaming the page's own code.
- **Screenshots must go to `/tmp` or inside the repo.** The browse tool rejects
  other paths (including the job tmp dir).

## 6. Edge-data degradations (expected, not bugs)

VideoService keys on a **string `template_gym` id** (`boxing`, `acro_yoga`, …),
**not** the real gym UUID — separate id spaces, no mapping (see the *VideoService
integration* section in `CLAUDE.md`). So `GET :8002/gyms/{uuid}` 404s for a real
CRM gym, and two surfaces degrade quietly **by design**:

- **Dashboard → "Upcoming Classes"** renders empty.
- **Schedule** shows "Could not reach the video service."

Don't file these as page failures. They resolve by seeding the gym into
VideoService or pointing the app at a `template_gym` id, not by touching the CRM.

## 7. Method note — one browser, sequential

The `browse` tool is a **single** headless-browser daemon, so a parallel
multi-agent sweep would have agents colliding on one session. Run the pages
**sequentially** in one browser. A true parallel sweep needs a browser instance
per agent on its own port — only set that up if the user explicitly wants it.

## Driving CanvasKit dialogs (wizards, pickers)

CanvasKit renders to a canvas, so DOM clicks can't reach dialog content
directly — but the semantics tree can be driven:

1. **Enable Flutter semantics** once per page load: JS-click the
   `flt-semantics-placeholder` element.
2. **Drive rows/buttons** via synthetic `MouseEvent`/`PointerEvent`
   dispatched on the matching `flt-semantics` node (`$B js`). `$B fill`
   works on semantics inputs.
3. **CTAs missing from the semantics tree** (some primary buttons):
   derive coordinates from a sibling semantics node's bounding rect and
   coordinate-click.
4. **Dev-server wedge**: after a browser restart, DDC may load every
   script but never run `main()` (stale DWDS debug session) — restart
   `flutter run`, then reload the page once.

## 8. Kiosk Mode: check-in + self-serve signup (no URL — driven by UI state)

**Kiosk views have no route at all — this is a harder version of the "can't be
clicked" gotcha in §3/§5, not just another page to `goto`.** Every other screen
in this skill is still reachable by URL fragment even when a dialog on it isn't
clickable. Kiosk Mode is different: `KioskSessionCubit` swaps the **entire**
authenticated subtree — `AuthGate` mounts `KioskScreen` *instead of*
`_MembersWorkspace` (see `CRM/CLAUDE.md`'s Kiosk Mode paragraph and the
`kiosk-guide` skill) — so there is no `#/kiosk` fragment, no deep link, and no
way to `$B goto` into any kiosk screen, ever. The **only** way in is: sign in as
staff with kiosk access, enable semantics, and tap the real nav item. Drive
every step below with the *Driving CanvasKit dialogs* technique above — this is
true for the admin nav rail tap that enters kiosk and for every kiosk screen
after that, since the kiosk is itself just more CanvasKit.

**Enter kiosk.** `owner1@test.com` (the seeded owner) has
`RolePolicy.canOperateKiosk`, so the standard dev-auto-login boot (§2) is
enough — no separate kiosk account exists.

1. Enable semantics, then find and tap the **"Kiosk Mode"** nav rail item.
2. A confirm dialog opens ("Enter Kiosk Mode?"); tap **"Enter Kiosk"**. This
   calls `enterKiosk()`, which flips the cubit and swaps the whole screen — the
   next `$B screenshot` should show the kiosk home (the name-search / QR split,
   "Start Trial / Membership" beneath it), with no nav rail and no admin chrome
   at all.
3. To leave and get the admin workspace back for further QA, tap the header
   padlock, confirm **"This signs the iPad out"** — this signs out
   completely (not just kiosk), so re-run dev auto-login (§2) to come back.

**Money paths use Stripe's documented test cards** in the signup's card step
— any future expiry, any 3-digit CVC, any 5-digit ZIP:

- `4242 4242 4242 4242` → succeeds (the happy-path and group-path runs below).
- `4000 0000 0000 0002` → a generic decline (the declined-card run below).

**Caveat to verify on first real run:** `CardFieldBox` (`flutter_stripe`'s
`CardField`) renders Stripe Elements as a **real HTML iframe on web**, not a
CanvasKit-painted control — it may be reachable by ordinary DOM interaction
rather than the semantics-tree technique above, or it may need the `browse`
tool's iframe/frame targeting if it has one. Confirm which on the first live
pass and update this note with the working recipe — don't guess at a command
that hasn't been proven against the real page.

**Solo happy path.** From the kiosk home, tap **"Start Trial / Membership"**,
then walk the spine (the New/Existing choice leads it, and Plan precedes
Waiver — see the `kiosk-guide` skill §11): tap **"I'm new here"** → fill the
details step (name/email/phone) → the optional extra-details step (skip or
fill address/DOB) → pick a plan → the waiver step (**"Sign and continue"**)
→ the card step (`4242…`, then **"Review"**) → the review step
(**"Sign Membership · $…"**) → Paying → **Welcome**. Screenshot at the review
step (confirm
the real plan price + due-today figure) and at Welcome.

**Duplicate-payer stop.** Run the details step again with the **same email**
as a payer who already exists (the member the happy-path run just created, or
any seeded member's email) and continue. The signup dead-ends on the
blame-free **"You already have an account here."** stop screen — no "Start
over" button (the fresh-card law forbids it; see `kiosk-guide` §3) — and it
auto-returns to the kiosk home on its own short hold, so just let it clear.
Confirm afterward, via the members list's **Incomplete** tab
(`http://localhost:8080/#/members`, then switch views), that the abandoned
shell shows up there with a **Finish signup** row action.

**Declined card.** Same spine as the happy path, but enter `4000 0000 0000
0002` at the card step and continue through to Pay. Confirm the **Declined**
screen appears with **"Try another card"** and **"Get help at the desk"** —
and confirms there is no "Start over" button here either (§2 of the
`kiosk-guide` skill: a declined payment has already committed a member row +
Stripe customer + signed waiver, so this is a front-desk handoff, not a retry
from scratch).

**Group / family path.** After the payer's own details step, the **"Anyone
else joining?"** roster step ("People") is always visited. Tap **"Add someone
new"**, fill that person's name/email, and continue — a new payee walks
match/no-match, per-person plan pick, and their own waiver (payer-auth first
if they're an existing member being linked, then their liability waiver),
before returning to the roster. Tap **Continue** to reach the **group review**
(one block per person, "Pay $…" totals every person's cart) and pay through to
Welcome the same way as the solo path.

## Keep this skill current

This is a living document (see `CLAUDE.md`). When a route is added/renamed, the
auto-login account changes, a new gotcha bites, or the page list grows, update
this file in the same change — a stale runbook sends the next QA pass to a dead
URL.
