# Kiosk Mode Phase G — Rotating QR Check-in Infrastructure (Design Plan)

**Status:** DESIGN ONLY — no implementation. Planning agent output, 2026-07-23.
**Parent plan:** visual plan `plan-586f6755256948e4` (Kiosk Mode), Phase G.
**Founder requirements (locked):** the kiosk iPad shows a QR that **rotates hourly**; a member's scan is accepted only when the presented token is from the **previous OR current hour** (server-authoritative); purpose is **proof of physical presence** (a screenshot expires — no check-in from home). **Founder additions (2026-07-23, same infra):** (1) the check-in QR encodes a **URL / universal link** — the CombatDen app intercepts it and runs the check-in; a regular phone camera opens the same URL in a browser and lands on the app-download page; (2) a **shared per-gym app-download page** we host, driven by per-gym store links on the gym table with CombatDen defaults.

**Two distinct QRs, one fallback destination — say it once, everywhere:** the **rotating CHECK-IN QR** (URL + hourly token, on the kiosk home) and the **static APP-DOWNLOAD QR** (stable per-gym URL, in the kiosk "Get the App" modal / welcome screen) are different codes with different jobs. For a phone **without** the app, both resolve to the same per-gym download page. For a phone **with** the app, only the check-in QR does anything special (universal-link intercept → check-in flow).

---

## 0. Grounding — what exists today (real files)

Repo root: `/var/home/jm/Documents/CombatDen/codebase/.claude/worktrees/kiosk-mode` (branch `worktree-kiosk-mode`, PR #59 open).

**Backend (`FastApiBackend/`)**
- `src/checkin/` — the consumer domain. `POST /api/v1/checkin` (staff-only, `verify_gym_employee_for_member(..., staff_roles=STAFF, gym_id=request.gym_id)`), addressing an occurrence by `(class_id, occurrence_date, occurrence_time)` = the ORIGINAL slot. `is_member=True` runs the strict kiosk gate: any blocking condition (`no_membership | out_of_classes | ineligible_plan | over_capacity | unsigned_waiver`) **rejects** with `log_id=null` + `skip_reason`, nothing written. Seams to reuse verbatim: `CheckinClassResolver.resolve(...) -> ResolvedClass` (pure read; enforces the 2h early window `settings.checkin_opens_hours_before_start`), `CheckinMemberGate.checkin_member(resolved, member_id, is_member, ignore_warnings)`, `StreakService.get_streak_details` (the router folds `class_streak_weeks` + `current_week_days` into `CheckinResponse` when `log_id` is non-null — `checkin_router.py:128-136`).
- `src/shared/auth.py` — verified-email identity. `verify_roles(gym_id, payload, STAFF)` = the staff gate (owner/admin/front_desk). `verify_member_self(member_id, payload, gym_id=...)` = THE member gate; today its only callers live in `src/member_portal/`.
- `src/member_portal/` — the member surface (`/api/v1/member/...`), thin handlers delegating to the same services the CRM uses. Three load-bearing rules: member_id never derived from the JWT; every gym-scoped route passes `gym_id` to `verify_member_self`; **no client-selectable gate semantics** (`is_member` etc. appear in no member-facing schema). Its CLAUDE.md currently documents "a member may not check themselves in" — Phase G deliberately amends this (see §3.2).
- `src/core/config.py` — every constant is a `Settings` field (env-overridable, monkeypatchable in tests).
- `src/core/dependencies.py` — the DI container (`DependencyInjector`); new domains register providers + `wiring_config.modules`.

**CRM (`CRM/`)**
- `lib/features/kiosk/` — Kiosk Mode (Phases B/C1/C2 built). `presentation/widgets/kiosk_qr_panel.dart` is the **static placeholder** this phase replaces (`_QrPlaceholder`, "deliberately inert"). `bloc/kiosk_flow_cubit.dart` drives the check-in lane (name search → class pick → `is_member: true` check-in via `MemberRepository.checkInMember(CheckInRequest(... isMember: true))` → glance/blocked). `bloc/kiosk_session_cubit.dart` = the 12h runway security shell. The kiosk runs INSIDE the authenticated CRM (staff Supabase JWT lives underneath) — the kiosk display is staff-authed by construction.
- `lib/features/schedule/data/occurrence_windows.dart` — the shared occurrence time-window predicates (`occurrenceCheckInOpen`, `occurrenceEnd`, `kCheckInOpensHours = 2`), used by the kiosk class pick.
- No QR-rendering dependency exists yet (`pubspec.yaml` has none).
- A "Get the App" **modal** (UX-5 ruling) is being built in parallel: an app-download QR + steps, reachable from the glance and the home QR area. **This plan changes what that modal's QR encodes** (the per-gym download page URL, not a raw store link — §6).

**MobileApp — two states, and it matters**
- THIS worktree's `MobileApp/` is the pre-productization prototype (no auth, no scanner, no dio-auth stack).
- **PR #60** (draft, branch `worktree-mobileapp-live`, worktree `.claude/worktrees/mobileapp-live`) productized it: Supabase auth (`supabase_flutter`), `core/network/api_client.dart` (bearer + bounded refresh-on-401), `AuthGate → MemberGate` revalidation ladder, `core/state/selected_member.dart` (`SelectedMember`, persisted + revalidated, member picked from `GET /api/v1/member/members` — the family/shared-email case), and a **stub QR check-in feature** `lib/features/qr_checkin/`: `checkin_scanner_screen.dart` (`mobile_scanner`, currently "ANY decoded barcode advances" — the class doc says "the kiosk Phase G nonce contract will replace" it), `checkin_pick_class_bloc.dart` (today's board via `MemberClassesRepository.getBoard`, drops cancelled, soonest-first), `checkin_confirm_screen.dart` + `checkin_confirm_body.dart` (celebration count-up, **no real POST**). Phase G's mobile side is *wiring a contract into this existing feature*, not building auth/scanner from scratch. It must be built on top of PR #60 (sequencing: §9 / OQ-1).

**Infra**
- Landing site: React SPA at `www.combatden.net` (S3 bucket `combatden-landing-www` + CloudFront `EDM1Y8AT0YDE7`, 404/403 → `index.html` SPA fallback). This is the natural host for the universal-link domain + the download page (§5–6).
- CRM at `app.combatden.net`; backend at `api.combatden.net` (open CORS).

---

## 1. The rotating-token model (the crux)

### 1.1 Recommended model: stored per-gym per-hour random tokens (DB rows), validated by server-clock bucket

**Bucketing.** An hour bucket is `date_trunc('hour', now() AT TIME ZONE 'UTC')` — computed by the **database clock**, never a device clock. UTC truncation sidesteps DST transitions and half-hour-offset timezones (gym timezone is irrelevant to the security property; buckets are opaque).

**Minting.** The kiosk-display endpoint (§3.1) *lazily materializes* the current bucket's token on read: `INSERT ... ON CONFLICT (gym_id, hour_start) DO NOTHING` + select — one row per `(gym_id, hour_start)`, token = 128-bit CSPRNG (`secrets.token_hex(16)`, 32 hex chars). Two kiosks at one gym race-safely converge on the same token. No scheduler, no cron: a gym whose kiosk is off mints nothing.

**Validation (the prev-OR-current window).** Given `(gym_id, token)` from the scan, the server loads this gym's rows for `hour_start IN (trunc(now), trunc(now) − 1h)` and accepts iff the presented token equals either row's token (comparison via `secrets.compare_digest`; cheap, and constant-time costs nothing). Everything is server time: a token minted at bucket H validates during H (current) and H+1 (previous) — real-world validity between **1h00m and 2h00m** depending on when within H it was captured. Anything older simply has no matching row in the two live buckets → rejected.

**Cleanup.** Opportunistic, in the mint transaction: `DELETE FROM gym_kiosk_tokens WHERE gym_id = :gym_id AND hour_start < :prev_bucket`. The table holds ≤2 live rows per gym with a kiosk running. No reconciler sweep needed (note: if we ever want belt-and-suspenders, `src/reconciler/` is the established home for such a sweep — not needed at this size).

**Reusable within its window — by design, not omission.** The QR is one code shown to *every* member for the hour, so the token is inherently multi-use. Per-member replay is governed by the existing check-in idempotency (`already_checked_in` per `(member, occurrence)`) and the strict gate; a member legitimately checking into two back-to-back classes reuses the same token — correct. Single-use tokens are impossible in this display model (they'd need per-scan rotation — see rejected Option C).

**Settings (per the no-magic-numbers rule, all `Settings` fields):**
- `kiosk_qr_rotation_seconds: int = 3600` — the bucket width. Kept configurable mainly so integration tests can shrink it to seconds; the product value is locked at hourly.
- `kiosk_qr_valid_buckets: int = 2` — current + previous. Locked at 2 by the founder's spec; a field so the window math has one named knob.

### 1.2 Considered and rejected

- **Option A — stateless HMAC** (`token = HMAC(secret, gym_id ‖ bucket)`, validate by recomputing for both buckets). Pros: no table. Cons: a secret to manage/rotate (env-global = one leak affects every gym; per-gym = a column, i.e. state anyway); **no revocation** of a leaked hour token short of secret rotation; subtle crypto to get right for zero operational gain at this scale. The DB-first stored-nonce model matches every convention in this codebase (tables + `.sql` files, DB as the one source of truth) and is trivially auditable. → Rejected.
- **Option B2 — token state as columns/JSONB on `gyms`** (current/prev token + bucket). Read-modify-write with race handling, rolling logic in app code, mixes ephemeral state into config. The dedicated 2-live-rows table is the leaner design despite being "another table" (DB-minimalism reading: minimal *moving parts*, not minimal *table count*). → Rejected.
- **Option C — per-scan / short-TTL rotation (30–60s), single-use** (WhatsApp-Web-style pairing). Strictly stronger anti-replay, but contradicts the founder's explicit hourly spec, requires the kiosk to poll every few seconds, and buys little for a low-stakes gamification surface. Documented as the future tightening knob (§7.3), not built.

### 1.3 What the QR encodes — a URL (founder directive), not an opaque string

The check-in QR encodes a **canonical HTTPS URL** carrying the gym and the rotating token:

```
https://www.combatden.net/checkin/<gym_id>/<token>
e.g. https://www.combatden.net/checkin/2f6c…a1/9f3a6c…e2
```

- **With the CombatDen app installed:** iOS Universal Links / Android App Links intercept the URL (path pattern `/checkin/*`) and open the app directly into the QR check-in flow with `(gym_id, token)` parsed from the path. On intercept the URL never touches our web server.
- **Without the app (regular camera):** the phone browser opens the URL; the landing SPA's `/checkin/*` route immediately forwards to the per-gym app-download page (`/get-app/<gym_id>`, §6), **dropping the token** (never logged, never carried in the redirect — the web page does nothing with it).
- The **in-app scanner** (member opens the app first and taps "Check in") decodes the same URL text with `mobile_scanner` and feeds the **same parser** — one parse function serves both entrances (scan and deep link).
- Path form over query params: shorter QR payload (~100 chars alphanumeric → low QR version, comfortably scannable at kiosk-tile size), cleaner AASA path matching. Host + exact shapes: OQ-12.
- The response of the mint endpoint returns the **fully-composed URL** (`qr_payload`) so the format lives in exactly one place (the backend); the CRM renders it blindly; the mobile parser is the one mirrored consumer (contract documented in the kiosk-guide skill, §9).

### 1.4 Clock skew — server-authoritative end to end

- **Validity:** decided only by DB `now()` at mint and at validation. The kiosk clock and the phone clock have zero say.
- **Kiosk refresh scheduling:** the mint response carries `server_now`, `expires_at` (end of the current bucket, UTC) and a derived `seconds_until_rotation: int`. The CRM schedules its next refetch off the **integer delta + monotonic elapsed time** (`Stopwatch`), never off local wall-clock arithmetic — mirroring the SEC-3 "server-anchored deadline" ruling from the kiosk security review. A rolled-back iPad clock can therefore neither extend nor break rotation; worst case the kiosk displays a stale QR, which the *server* still bounds via the prev-bucket grace, then rejects.
- **Hour-boundary handoff:** a member who scans at :59 and submits at :01 presents the now-previous bucket's token → accepted. This is the main *functional* reason the prev-hour window exists (the security reason is walk-in-at-:59 usability; both are served by the same rule).
- **Phone clock:** irrelevant — the phone only relays the token string.

---

## 2. Data model

### 2.1 New table: `gym_kiosk_tokens`

`Database/supabase/schemas/gym_kiosk_tokens.sql` (+ matching `access_rules/gym_kiosk_tokens.sql`), hand-written migration per `Database/CLAUDE.md` (delegated to a sub-agent; the user runs it; version-prefix collision check after any merge).

```sql
CREATE TABLE gym_kiosk_tokens (
    gym_id     UUID        NOT NULL
        CONSTRAINT fk_kiosk_token_gym REFERENCES gyms(gym_id),
    hour_start TIMESTAMPTZ NOT NULL,          -- UTC hour-truncated bucket
    token      TEXT        NOT NULL CHECK (token <> ''),  -- 32-hex CSPRNG
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_gym_kiosk_tokens PRIMARY KEY (gym_id, hour_start)
);
```

- **Access rules:** RLS enabled; NO policies for `authenticated`/`anon` at all; `REVOKE ALL ... FROM authenticated` (the `resource_locks` / `stripe_webhook_events` pattern — pure service-role infrastructure). The token must never be readable through any client-facing path except the staff-gated mint endpoint.
- **Not** in `immutable_columns.py` (no user-facing update path exists — the guard is for client update requests). Not seeded. Add to `schema_db_diagram.io`.
- Growth: ≤ 24 rows/gym/day worst case, opportunistically deleted on mint (≤ ~2 live rows per active gym).

### 2.2 New columns on `gyms`: per-gym app store links (founder addition 2)

In `Database/supabase/schemas/gyms.sql`:

```sql
    -- White-label app listings. NULL = this gym uses the CombatDen app's own
    -- store listings (backend Settings defaults). Set only for gyms with
    -- their own published white-label app.
    app_store_url  TEXT,   -- iOS App Store listing
    play_store_url TEXT,   -- Google Play listing
```

- Nullable TEXT, **NULL = fall back to CombatDen defaults** (`Settings.default_app_store_url` / `Settings.default_play_store_url` — env-configured, so the day the CombatDen listings go live is an env change, not a deploy).
- Client-editable in principle (owner/admin gym-config surface), so NOT in the `GYMS` immutable frozenset; whether to expose edit UI now is OQ-16 (the columns + resolution logic ship regardless; a white-label gym can be set by ops/SQL until the UI exists).
- Two explicit columns (not a JSONB blob): exactly two platforms, each independently overridable, queried by a public endpoint — the flat columns are the lean shape here.

### 2.3 What is stored vs derived

| Thing | Stored / derived |
|---|---|
| Hour token | Stored (`gym_kiosk_tokens`), lazily minted |
| Validity window | Derived at validation from DB `now()` (2 bucket lookups) |
| QR payload (URL) | Derived by the backend at mint-read (one composer) |
| Check-in outcome | Existing `member_attendance` write via the existing gate — Phase G stores **nothing new** about a check-in |
| Per-gym store links | Stored (`gyms.app_store_url` / `play_store_url`), resolved against Settings defaults at read |

No "scan log" table in v1: a validated scan becomes a normal attendance row (with the existing activity/streak machinery); a rejected token is a backend log line. A dedicated scan-audit table is deliberate YAGNI (revisit only if abuse monitoring demands it — OQ-9).

---

## 3. Backend — new `src/kiosk/` domain + one member-portal route

### 3.1 Domain layout (per FastAPI CLAUDE.md conventions — domain-prefixed files, flat `service/`, SQL in files)

```
src/kiosk/
├── kiosk_router.py                  # the STAFF-facing mint route
├── schema/kiosk_schema.py           # KioskQrTokenResponse, KioskCheckinRequest,
│                                    # KioskTokenRejectReason (StrEnum, API-only)
├── service/kiosk_token_service.py   # KioskTokenService: current(), validate()
└── sql/
    ├── kiosk_token_mint.sql         # INSERT ... ON CONFLICT DO NOTHING + prune stale
    ├── kiosk_token_current.sql      # SELECT the (gym, current-bucket) row
    └── kiosk_token_validate.sql     # SELECT tokens for the two live buckets
```

- Bind-param casts are `CAST(:x AS UUID/TIMESTAMPTZ)` (never `:x::type`); no `:word` in SQL comments.
- DI: `kiosk_token_service = providers.Singleton(KioskTokenService, db_pool=db_pool, settings-injected knobs)`; add `src.kiosk.kiosk_router` and the member-portal module wiring to `wiring_config.modules`. Update `README.md` + `architecture.mermaid` (new domain + routes) in the same change, via the `mermaid-creation` skill.

**`KioskTokenService`** (all bucket math in one place):
- `current(gym_id) -> KioskTokenView` — one transaction: prune stale rows, upsert the current bucket, read it back; compose `qr_payload` from `Settings.kiosk_checkin_url_base` (e.g. `https://www.combatden.net/checkin`) + gym + token; return token, `hour_start`, `expires_at`, `server_now`, `seconds_until_rotation`.
- `validate(gym_id, token) -> bool` — the two-bucket lookup + `compare_digest`. Purely a read.

### 3.2 Endpoints

**(1) Kiosk display mint — staff-authed, in `kiosk_router.py`:**

```
GET /api/v1/kiosk/{gym_id}/qr-token
  auth: verify_roles(gym_id, user_payload, STAFF)     # owner/admin/front_desk —
                                                      # matches canOperateKiosk
  200: KioskQrTokenResponse {
        gym_id, qr_payload,            # the full URL — clients render it blindly
        expires_at, server_now,        # absolute UTC, informational
        seconds_until_rotation: int    # what the CRM actually schedules on
      }
```

GET-with-lazy-materialization follows the `GET /video-rec` precedent (a read that records its serve); repeated calls in one bucket are idempotent (same token). The raw `token` need not be a separate field — `qr_payload` carries it; keep the response minimal.

**(2) Member scan check-in — member-authed, as a route in `member_portal_router.py`** (the member surface owns every `verify_member_self` gate; the handler stays thin and composes kiosk + checkin services):

```
POST /api/v1/member/gyms/{gym_id}/members/{member_id}/kiosk-checkin
  auth: verify_member_self(member_id, user_payload, gym_id=gym_id)
  body: KioskCheckinRequest {
        qr_token: str,                # the token parsed from the scanned URL
        class_id: UUID,
        occurrence_date: date,        # ORIGINAL slot — same addressing as every
        occurrence_time: time,        #   occurrence API in the system
      }
  200: CheckinResponse               # the EXISTING schema, reused verbatim —
                                     # log_id/skip_reason/points_awarded/
                                     # already_checked_in/class_streak_weeks/
                                     # current_week_days
  403: {"detail": "invalid_token" | "expired_token"}   # token capability failed
  400/404: resolver errors (bad occurrence / class not found), as the staff route
```

Handler order (composition, no duplication):
1. `verify_member_self(member_id, gym_id=gym_id)` — the member is themselves, at this gym (family emails resolved by the explicit `member_id`, per member-portal rule #1).
2. `KioskTokenService.validate(gym_id, request.qr_token)` — **403 with a typed detail** on failure. Distinct transport from gate rejections on purpose: a token failure means *go rescan at the kiosk*; a 200 + `skip_reason` means *see the front desk*. (`invalid_token` vs `expired_token`: we can only distinguish them if validation also peeks at recently-pruned buckets — simplest honest v1: return `invalid_token` always, since a stale token is indistinguishable from a forged one once its row is pruned. The app copy treats both as "code expired — scan the current code". OQ-8 if the founder wants the distinction badly enough to keep a few extra buckets around.)
3. `CheckinClassResolver.resolve(class_id, gym_id, occurrence_date, occurrence_time)` — the existing seam (2h early window included).
4. **New server-side upper bound for self-serve (recommended, OQ-2):** reject an occurrence that already **ended** (`resolved.occurred_at + duration_minutes ≤ now` → 400 `"class_ended"`). The staff route deliberately allows retro check-ins (corrections); a member self-serve surface must not write retroactive attendance. This is a guard **in the kiosk-checkin path only** — the shared resolver is untouched, mirroring how the CRM kiosk applies its own tighter client window (UX-1).
5. `CheckinMemberGate.checkin_member(resolved, member_id, is_member=True, ignore_warnings=False)` — **both flags hardwired server-side**, satisfying member-portal rule #3 (no client-selectable gate semantics; the exact hole the old self-branch had).
6. On `log_id` non-null: fold `StreakService.get_streak_details` exactly as `checkin_router.py` does.

**Doc amendment required (same change):** `FastApiBackend/CLAUDE.md`'s member-portal section says a member may not check themselves in *because it bypasses the front desk and the waiver gate*. Phase G's route does neither: the rotating token IS the front-desk-presence proof, and the strict gate still enforces `unsigned_waiver` (a member with an unsigned waiver is rejected to the front desk). Update that paragraph and the member-portal route table; also update `src/shared/auth.py`'s docstring claim that member-portal is the only member-facing surface caller if the route lands there (it does — no change needed if the route lives in `member_portal_router.py`, which is exactly why it should).

**(3) Public app-links read — unauthenticated, tiny (founder addition 2, consumed by the download page §6):**

```
GET /api/v1/gyms/{gym_id}/app-links        (in src/gyms/ — a gym read, not kiosk)
  auth: NONE (deliberately public; returns only store URLs + gym name)
  200: { gym_name, app_store_url, play_store_url }   # resolved: gym override
                                                     # else Settings defaults
  404: unknown gym
```

Public on purpose: the data is marketing-grade (store listing URLs), the page fetching it is unauthenticated, CORS is already open. It must never grow richer gym data without revisiting auth. (Placement in `src/gyms/` vs `src/kiosk/`: it's a gym-config read used beyond the kiosk → `src/gyms/`.)

### 3.3 New Settings

```
kiosk_qr_rotation_seconds: int = 3600
kiosk_qr_valid_buckets: int = 2
kiosk_checkin_url_base: str = "https://www.combatden.net/checkin"
default_app_store_url: str = <CombatDen iOS listing — placeholder until published>
default_play_store_url: str = <CombatDen Android listing — placeholder until published>
```

### 3.4 Tests (backend)

- **Unit:** bucket truncation math; window acceptance (current / previous / older-by-one-second rejected); payload composition; `compare_digest` path.
- **Integration** (real local Supabase, `created`-fixture cleanup — the new rows are cleaned by the mint prune + explicit test deletes): mint idempotency within a bucket; two-bucket acceptance by inserting a synthetic previous-bucket row via a `tests/helpers/db_writes.py` inline write (the sanctioned test-SQL exemption); full scan flow — create a member + class occurrence via the data factory, obtain a **member JWT** the same way the existing `tests/member_portal/` suite does (Supabase admin client creating a confirmed user on the member's email — reuse that suite's auth helper rather than inventing one), then: valid token → 200 recorded + streak folded; stale token → 403; wrong-gym token → 403; unsigned-waiver member → 200 + `skip_reason=unsigned_waiver`, nothing written; ended occurrence → 400 (if OQ-2 lands); repeat scan → `already_checked_in=true`, points echoed not re-awarded. Shrink `kiosk_qr_rotation_seconds` via `settings` monkeypatch where a live rotation is exercised.
- Gate: `.venv/bin/python -m ruff check src/ tests/` + `python -m pytest` (broken venv shebangs — always `python -m`).

---

## 4. Kiosk display side (CRM)

### 4.1 New pieces (per CRM feature conventions)

- `lib/features/kiosk/data/repositories/kiosk_repository.dart` — wraps `ApiClient`: `Future<KioskQrToken> getQrToken(String gymId)`; model `lib/features/kiosk/data/models/kiosk_qr_token.dart` (`json_serializable`, mirrors `KioskQrTokenResponse`; regenerate `*.g.dart`).
- `lib/features/kiosk/bloc/kiosk_qr_cubit.dart` (+ state) — a small dedicated cubit provided at `KioskScreen` level (the QR lifecycle is orthogonal to `KioskFlowCubit`'s flow navigation; bolting rotation timers onto the flow cubit would bloat it). Injectable `now`/timer seams for `bloc_test`.
- `kiosk_qr_panel.dart` — replace `_QrPlaceholder` with a `BlocBuilder<KioskQrCubit, ...>` rendering the live QR in the **same framed tile** (`DesignConstants.heroChartHeight`, `surface`, `radiusCard`, `cardShadow` — the frame already matches the approved mockup; only the tile's inner content changes). This is a scoped visual change: run it through a **dedicated Opus `impeccable` subagent** at build time per the repo rule (the three tile states below are the ambiguity that rule exists for).

### 4.2 Rotation behavior

- On kiosk entry: fetch. Schedule the next fetch at `seconds_until_rotation` (server-derived int) **+ 2s settle jitter**, counted on monotonic elapsed time — never local wall-clock math (SEC-3 mirror; a clock rollback cannot stretch the display schedule).
- On fetch failure: keep showing the **previous QR** (it remains server-valid through the prev-bucket grace — this is the offline story working *for* us) and retry on a backoff (e.g. 30s → 60s, capped). Track "displayed token age" from fetch time (monotonic); once it exceeds `seconds_until_rotation + rotation period` (i.e. the server can no longer accept it), flip the tile to a **degraded state**: calm copy ("Code unavailable — check in with your name"), name-search unaffected. Recovery on the next successful fetch.
- Tile states: `loading` (skeleton in the frame, first fetch only) / `live` (QR) / `degraded` (fallback copy). The section head ("Scan with app") and `KioskAppLine` stay as-is.
- No per-scan feedback on the kiosk: the phone is the feedback surface (the kiosk doesn't know a scan happened — deliberate; no poll-for-scan channel in v1).

### 4.3 QR rendering dependency

Add **`qr_flutter`** (pure-Dart QR painter, web-safe) via `flutter pub add`. Shared by this panel AND the "Get the App" modal's static QR (§6.4). Document it in the CRM CLAUDE.md dependency list (scoped: QR rendering only). `make analyze` + `bloc_test` coverage for the cubit (rotation scheduling, failure retry, degraded horizon, dispose cancels timers).

---

## 5. The check-in URL as a universal link (founder addition 1)

### 5.1 URL + association design

- **Canonical URL:** `https://www.combatden.net/checkin/<gym_id>/<token>` (host = the landing domain; exact host/path shapes OQ-12).
- **iOS Universal Links:** serve `https://www.combatden.net/.well-known/apple-app-site-association` (JSON, no extension, `Content-Type: application/json`) listing the CombatDen app's `<TeamID>.<bundle-id>` with path pattern `/checkin/*`. The app adds the Associated Domains entitlement `applinks:www.combatden.net`.
- **Android App Links:** serve `/.well-known/assetlinks.json` with the app's package name + release-signing SHA-256 fingerprint; the app declares an auto-verified intent filter for `https://www.combatden.net/checkin`.
- **Hosting the association files:** static objects in the `combatden-landing-www` bucket. The landing deploy script must upload them with the exact content type and they must resolve as real objects (NOT fall through the SPA 404→index fallback — CloudFront only falls back when the object is missing, so uploading them as real keys suffices). Deploy-script addition noted in §9.
- **Prerequisites (founder ops, OQ-13):** Apple Team ID + bundle id, Android package + release keystore SHA-256, and — for links to verify in the wild — the app actually published (App Links verification and UL behavior are tied to installed, store-signed builds; dev testing uses debug overrides). The association files can ship ahead of store presence harmlessly.
- **White-label caveat:** only the **CombatDen** app is associated in v1. A future per-gym white-label app intercepting the same domain would require adding its appID to the association files (any installed listed app may claim the path — messy across gyms). v1 scope: CombatDen app only; white-label apps' members use the in-app scanner. (OQ-14.)

### 5.2 In-app handling (MobileApp, on the PR #60 substrate)

- Add the **`app_links`** Flutter package (cold-start initial link + warm link stream).
- ONE parser (`lib/features/qr_checkin/data/checkin_link.dart` or similar): URL text → `CheckinLink{gymId, token}` — consumed by BOTH the deep-link handler and the in-app scanner's `onDetect` (which today accepts anything; Phase G makes it parse, show a gentle inline "Not a check-in code" state on non-matching payloads — e.g. someone scanning the app-DOWNLOAD QR from inside the scanner — and keep scanning).
- Deep-link entry states:
  - Signed in + `SelectedMember` set → straight into the check-in flow (§5.3), with a gym-mismatch check first.
  - Signed in, multiple member rows → member picker, then continue (family case; the link is held while picking).
  - Signed out → hold the pending link through the sign-in flow, then continue (the token lives ≥1h, so this is safe and worth the plumbing). Fallback if this proves gnarly in v1: after sign-in show "Scan the code again" — OQ-5.
- **Gym mismatch:** link gym ≠ selected member's gym → if the account holds a member row at the link's gym, offer a one-tap switch (or auto-switch, OQ-6); else a clear "This code belongs to <gym>" error.

### 5.3 The scan→check-in flow (wiring the PR #60 stub)

1. **Scanner / deep link** → `CheckinLink{gymId, token}`.
2. **Pick class** — reuse `CheckinPickClassBloc`'s today-board read, tightened to mirror the kiosk's fixed UX-1 rules (drop ended occurrences, current-first ordering, `occurrenceCheckInOpen` 2h window — port the same predicate semantics; MobileApp has its own copy of the window helper on PR #60's home feature). Auto-advance when exactly one occurrence is open (OQ-3) vs always show the pick list (PR #60's built behavior) — founder call; the pick list must exist either way for multi-class hours.
3. **Submit** — `POST /api/v1/member/gyms/{g}/members/{m}/kiosk-checkin` with `{qr_token, class_id, occurrence_date (original), occurrence_time (original)}` through the existing `ApiClient`. New repository method in the `qr_checkin` feature (Screen → Bloc → Repo → ApiClient, no skipped layers).
4. **Outcomes the member sees** (mirroring the kiosk's blame-free front-desk handoff law):
   - `log_id` set, fresh: the existing confirm/celebration screen goes real — `points_awarded` count-up, `class_streak_weeks` + `current_week_days` (the same data the kiosk glance shows; the response carries it all, zero extra fetches).
   - `already_checked_in`: calm "You're already checked in ✓" variant (points echoed, no new +N celebration).
   - `skip_reason` (200): rejection screen mapping the enum to blame-free copy + "See the front desk" — `unsigned_waiver` → "needs a quick signature at the front desk", `over_capacity` → "this class is full", `no_membership`/`out_of_classes`/`ineligible_plan` → "the front desk can sort this out". Same copy family as the kiosk blocked screen (compose from it, don't redesign).
   - 403 token failure: "That code has expired — scan the code on the kiosk screen" → back to scanner.
   - `class_ended` 400 (if OQ-2 lands): "This class already ended" → back to pick.
   - Network: retry affordance.
- Tests: parser unit tests; bloc tests for gym-mismatch, submit outcome mapping, pending-link-through-auth; `flutter analyze` clean.

---

## 6. The shared per-gym app-download page (founder addition 2)

### 6.1 What it is

ONE small web page we host: given a gym, it detects the platform and forwards to the **right store listing for that gym** (per-gym white-label override, else the CombatDen defaults). Explicitly consumed by:
(a) the check-in QR's regular-camera fallback (`/checkin/*` → forwards here, token dropped),
(b) the kiosk "Get the App" modal's **static QR** (encodes this page's URL for the gym),
(c) every "get the app in the App Store" text nudge (kiosk app-line, welcome screen, glance footer).

### 6.2 URL + hosting

- **URL:** `https://www.combatden.net/get-app/<gym_id>` (consistent path-style with `/checkin/...`; shapes OQ-12).
- **Hosting: the existing LandingPage React SPA** (recommended). The SPA's 404→index fallback already routes any path to React; add two routes: `/get-app/:gymId` (the page) and `/checkin/:gymId/:token` (immediate `replace` to `/get-app/:gymId`, token discarded). No new bucket, no new distribution, the domain matches the universal-link association. Alternative (standalone static HTML uploaded beside the SPA) rejected: two page stacks to style/deploy for one tiny page, and dynamic path segments fit the SPA fallback naturally. **Guard:** landing memory notes `EXCLUDE_PREFIXES` protects `one_pager/` — the new routes are React-side only, no bucket-layout change beyond the two `.well-known` files (§5.1).
- **Behavior:** on load, fetch `GET api.combatden.net/api/v1/gyms/<gym_id>/app-links` (public, §3.2-3). UA-based platform detection: iOS → resolved App Store URL, Android → resolved Play URL (auto-redirect); desktop/unknown → a simple chooser page showing both badges + the gym's name. Fetch failure or missing/invalid gym → CombatDen default links (baked into the page as last-resort constants). No JS-heavy cleverness — this page must work on any phone browser instantly.
- Copy/design: minimal branded page (gym name, "Get the CombatDen app", store badge) — marketing surface, so author copy with the `marketing-language` skill and keep it landing-styled; an `impeccable` pass at build time.

### 6.3 Resolution rule (one place, the backend)

`app-links` endpoint resolves: `gym.app_store_url ?? settings.default_app_store_url`, same for Play. The page never encodes store links per-gym in QR payloads — the **page URL is stable per gym forever** (that's what makes the download QR static and printable) while the listing links stay editable behind it.

### 6.4 Integration with the in-flight "Get the App" modal

The UX-5 modal being built now plans "a static QR encoding the App Store link". **Change (flag to the modal workstream): the modal's QR must encode `https://www.combatden.net/get-app/<selectedGym.gymId>` instead** — otherwise Android members scan an iOS link and white-label gyms can never be routed. Same for the welcome screen's QR (Phase D tail) and any printed material. The CRM composes the URL from a shared helper (one constant base + gymId — mirror of the backend's `kiosk_checkin_url_base` pattern; a CRM `AppConstants` entry).

---

## 7. Proof-of-presence security analysis

### 7.1 Threat walk

| Attack | Outcome |
|---|---|
| **Forge a token** | 128-bit CSPRNG, validated by DB lookup + `compare_digest`. Guessing needs a valid member JWT per attempt (the scan route is member-authed) against 2 live tokens/gym — infeasible; failures logged. |
| **Screenshot at the gym, check in from home later** | Dead once the token's bucket ages out of {current, previous} — worst case 2h00m, best 1h01m after capture. This is precisely the founder's requirement: the *trivial permanent* replay is dead. |
| **Screenshot relayed to a friend at home within the window** | The residual cheat: works if a checkin-open occurrence exists in that window (the 2h-early gate + the recommended `class_ended` bound also constrain it). Accepted residual risk for a points-gamification surface — see 7.2/7.3. |
| **Replay of another member's scan request** | TLS + member JWT: the POST only ever checks in the *authenticated* member for themselves. Replaying your own request hits `already_checked_in` idempotency. Zero cross-member effect. |
| **Wrong-gym / cross-gym scan** | Triple-layered: the token validates only against the URL's `gym_id`; `verify_member_self(gym_id=path)` pins the member row to that gym; `member_attendance`'s composite FK `(member_id, gym_id)` is the final wall. |
| **Steal the token remotely (no gym visit)** | The mint endpoint needs a staff JWT; the token otherwise exists only on the kiosk screen (physically at the gym) and in QR URLs members scanned there. The browser-fallback path drops the token immediately and never transmits it anywhere (§5.1); it can appear in CloudFront request logs for no-app scans — short-lived, gym-public data; acceptable, noted. |
| **Member reaches staff surfaces via kiosk/QR infra** | Nothing new opens: the scan route is on the member portal with hardwired `is_member=True`, `ignore_warnings=False`; no client-selectable gate semantics anywhere (member-portal rule #3 held). |
| **Kiosk iPad clock rollback** | Display-side only; server validity is untouched. Refresh scheduling is server-delta + monotonic (§4.2). |
| **Waiver bypass** | Impossible: the strict gate rejects `unsigned_waiver` — the legal gate is *stronger* here than the staff path (no override exists on the member route). |

### 7.2 The prev+current window tradeoff, stated honestly

- **Usability it buys:** the :59-scan/:01-submit boundary case; a kiosk that missed one refresh (network blip) keeps a valid code for up to an hour; a member who scans on walk-in and picks a class after warm-up.
- **Tightness it costs:** effective validity 1h–2h. Within it, presence is transferable (relay a screenshot). The check-in still requires: a member account at that gym, an occurrence open for check-in in that window, and passes the strict gate. Value of the cheat ≈ streak/points inflation; cost of tightening ≈ boundary-case rejections at the kiosk. The founder has priced this correctly for the stakes.

### 7.3 Tightening knobs (documented, not built)

1. Shrink `kiosk_qr_rotation_seconds` (e.g. 15 min buckets → ≤30 min validity) — a Settings change, zero code.
2. Per-scan short-TTL codes (Option C) — the endgame if abuse ever materializes; requires kiosk polling + a different display model.
3. Per-member invalid-token rate limiting (429 after N failures/min) — cheap hardening, OQ-9.
4. A scan-audit table for abuse monitoring — YAGNI now (§2.3).

---

## 8. Edge cases catalogue

- **Hour boundary mid-flow:** scan :59:50 → submit :00:30 → prev-bucket accept. ✔ by design.
- **Slow member:** scan, then >2h on the pick screen → 403 expired → "rescan"路 back to scanner. The app flow needs no idle timer of its own (the token expiry IS the timer).
- **Kiosk entered mid-hour:** mints the in-progress bucket; first rotation at the top of the next hour (`seconds_until_rotation` < 3600 on the first fetch — the cubit just schedules what the server says).
- **Backend down at rotation:** kiosk keeps the old QR (server-valid ≤1h more), retries on backoff; then tile degrades to name-search copy; name-search lane unaffected (it has its own failure handling).
- **Two iPads, one gym:** both mint-on-demand → `ON CONFLICT` converges on one token. ✔
- **Gym with kiosk off:** no rows minted; any presented URL rejects. (A member can only obtain the URL from a running kiosk anyway.)
- **Member scans the app-DOWNLOAD QR with the in-app scanner:** parser sees `/get-app/...` — not a check-in link → inline "Not a check-in code" (optionally: recognize it and just dismiss with "You already have the app ✓" — copy nicety, build-time call).
- **No-app member scans the CHECK-IN QR with the camera:** browser → `/checkin/*` → forwarded to `/get-app/<gym>` → store. One QR serves both audiences (the founder's directive, working as intended).
- **Family/shared email:** deep link → member picker when several rows exist; `member_id` always explicit in the POST.
- **Member signed out when the link fires:** pending-link-through-auth (§5.2, OQ-5).
- **Unsigned waiver / over capacity / no membership / out of classes / ineligible plan:** strict-gate `skip_reason` → blame-free copy + front-desk handoff (§5.3).
- **Repeat scan same class:** `already_checked_in` — calm confirm, no double points (existing idempotency).
- **Back-to-back classes:** same token, two submissions — legitimate, supported (token is bucket-reusable; §1.1).
- **Occurrence rescheduled/cancelled between pick and submit:** the resolver re-resolves at submit; a cancelled occurrence 400s → friendly retry/pick again.
- **Half-hour timezones / DST:** UTC bucketing — no effect on validity; occurrence addressing stays gym-local original-slot (existing system, untouched).
- **Token in browser history/logs (no-app scan):** dropped on forward, never acted on server-side by the web page; expires ≤2h. Accepted (§7.1).
- **Gym has its own white-label app:** download page routes to ITS store listings (`gyms.app_store_url`/`play_store_url`); universal-link intercept remains CombatDen-app-only in v1 (OQ-14).

---

## 9. Rollout, sequencing, verification, docs

**Sequencing (recommendation — OQ-1 for the founder):**
1. **DB migration** (`gym_kiosk_tokens` + `gyms` store-link columns + access rules) — hand-written by a sub-agent, user runs it. Check version-prefix collisions post-merge.
2. **Backend** (`src/kiosk/` + member-portal route + public app-links read + Settings + tests) — additive; can ride the kiosk worktree.
3. **CRM kiosk panel** (repository + cubit + live tile + `qr_flutter`) — ships with (2) in one PR so the panel never points at a missing route. Whether this joins PR #59 or a new Phase-G PR: founder call (PR #59 is already under review — a separate PR keeps it reviewable).
4. **Landing page** (get-app + checkin routes, `.well-known` association files, deploy-script content-type handling) — independent, deployable anytime after (1)–(2) define the URL shapes.
5. **Kiosk "Get the App" modal QR retarget** (§6.4) — coordinate with the in-flight UX-5 workstream *now* so it isn't built against a raw store link and reworked.
6. **MobileApp wiring** — **on top of PR #60** (merge #60 first, then a Phase-G-mobile PR on main; or stack a branch on `worktree-mobileapp-live`). Building it in the kiosk worktree's stale MobileApp is the one clearly wrong option.
7. Store/association prerequisites (OQ-13) run in parallel as founder ops.

**Verification:** backend ruff + pytest incl. the live member-JWT integration flow (§3.4); CRM `make analyze` + `make test` + a live `make run` kiosk session scanning with a dev phone build; mobile `flutter analyze` + tests + a physical-device scan against local backend; landing page manual UA-matrix check (iOS Safari / Android Chrome / desktop) + AASA/assetlinks content-type curl checks.

**Docs to update in the same changes (living-documents rule):**
- `FastApiBackend/CLAUDE.md` — member-portal route table + the "may not check themselves in" paragraph (amended per §3.2), new domain listed; `README.md` + `architecture.mermaid` (new domain/routes, `mermaid-creation` skill).
- `Database/` — `schema_db_diagram.io`, this CLAUDE.md's table notes if warranted.
- `CRM/CLAUDE.md` — kiosk paragraph ("live per-scan QR is Phase G" → live), `qr_flutter` dependency line.
- MobileApp CLAUDE.md (on the #60 substrate) — qr_checkin goes real; `app_links` dependency.
- **kiosk-guide skill (Phase F)** — the QR contract (URL shape, bucket/window rule, endpoint pair, rejection mapping) becomes a section; until Phase F exists, this plan file + memory are the record.
- Vault: `Concepts/Product/Mechanisms/QR_Scan_Engagement` still documents "scan-not-kiosk" — Phase G shipping makes the deferred pivot doc worth revisiting (OQ-11; vault workflow: office-hours/pivot doc BEFORE strategy-doc edits).

**Hard-to-reverse decisions (flagged):**
1. **The QR URL shape + host** — printed on screens and (via the download QR) potentially on physical material; the universal-link association binds the app to the domain. Choose once (OQ-12).
2. **`gym_kiosk_tokens` table shape** — low risk (ephemeral rows), but the `(gym_id, hour_start)` PK bakes in the bucket model.
3. **`gyms` store-link columns** — flat two-column shape; fine unless a third platform materializes.
4. **The member-portal kiosk-checkin route path + request schema** — a mobile-app-consumed contract; version it right the first time (`CheckinResponse` reuse keeps the response side stable).
5. **The white-label universal-link stance** (CombatDen-app-only association, v1) — adding per-gym apps later touches the association files and UX (OQ-14).

---

## 10. Open Questions (founder decisions — nothing below is assumed)

**Sequencing / process**
- **OQ-1 — PR topology & order:** Phase-G backend+CRM in PR #59 vs a fresh PR? Mobile wiring stacked on `worktree-mobileapp-live` vs after #60 merges? (Recommended: fresh Phase-G PR after #59 merges; mobile after #60 merges.)
- **OQ-11 — vault:** write the QR_Scan_Engagement pivot doc now that Phase G is defined (the earlier "skip for now" predates this design)?

**Token / scan contract**
- **OQ-2 — self-serve upper bound:** reject already-**ended** occurrences on the member kiosk-checkin route (recommended)? If yes, exact rule: until occurrence end (recommended — matches the CRM kiosk's UX-1 client filter) vs start + fixed grace?
- **OQ-3 — pick-class step:** auto-advance when exactly ONE occurrence is open, or always show the pick list (PR #60's current build)?
- **OQ-5 — deep link while signed out:** hold the pending link through sign-in and continue (recommended; token lives ≥1h) vs simple "sign in, then scan again"?
- **OQ-6 — gym mismatch in-app:** auto-switch the selected member to the scanned gym when the account has a row there, or prompt first?
- **OQ-8 — 403 detail granularity:** single `invalid_token` (recommended; stale и forged are indistinguishable once pruned) vs keeping extra buckets around to say `expired_token` distinctly?
- **OQ-9 — rate limiting:** add per-member invalid-token throttling now, or defer (logging only) until there's any sign of probing? (Recommended: defer.)

**URL / web / association**
- **OQ-12 — canonical shapes:** host (`www.combatden.net` vs apex vs a short subdomain like `go.combatden.net`) and paths (`/checkin/<gym>/<token>`, `/get-app/<gym>` — path-style recommended) — locked once printed.
- **OQ-13 — association prerequisites (founder ops):** Apple Team ID + bundle id, Android package + release-cert SHA-256, and the store-publishing timeline for the CombatDen app (universal/app links verify fully only for store-signed installs; also: what do `default_app_store_url`/`default_play_store_url` point at until the listings exist — a "coming soon" landing section?).
- **OQ-14 — white-label apps vs universal links:** confirm v1 = only the CombatDen app intercepts `/checkin/*`; white-label-app members use the in-app scanner (their apps aren't associated with our domain).
- **OQ-15 — `/checkin` browser fallback copy:** plain forward to the download page vs a one-liner of context ("Get the app to check in") on arrival?

**Gym store links**
- **OQ-16 — edit surface:** ship the `gyms.app_store_url`/`play_store_url` columns + resolution now with ops-only population (recommended), or also build the owner/admin gym-settings edit UI in this phase?
- **OQ-17 — desktop/unknown-UA behavior on the download page:** dual-badge chooser (recommended) vs default to one store?
