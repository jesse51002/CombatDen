# CombatDen — Production Deployment (demo)

First production deployment. A live, public, HTTPS demo of the gym-owner admin
app backed by its two read-only APIs, on `combatden.net`. AWS account
`259645229668`, region `us-east-1`. DNS is manual at **Squarespace**.

```
app.combatden.net     → CloudFront → S3 (combatden-app)         static Flutter build/web
themes.combatden.net  → CloudFront → S3 (combatden-themes)      static Flutter build/web (theme browser)
theme.combatden.net   → App Runner → ECR combatden-themeservice  uvicorn :8000  (output.yaml metadata; images on CDN)
video.combatden.net   → App Runner → ECR combatden-videoservice  uvicorn :8002  (reads Supabase Postgres)
cdn.combatden.net     → CloudFront → S3 (combatden-assets)       theme images/icons (PNG/SVG, OAC)
```

`themes.combatden.net` is the **public theme browser** — a second build target of
the same `CRM/` Flutter project (`--target lib/main_theme_browser.dart`),
not a separate app. It hits the same two read-only APIs. The marketing landing
page just links to it (and it links back). See `CRM/CLAUDE.md`
→ *Standalone theme browser*.

The app build bakes in the two API URLs via `--dart-define` (CUST_BASE_URL,
VIDEO_BASE_URL). CORS on both APIs is `["*"]`; both are GET-only, no auth.

> **⚠️ Platform note — migrate off App Runner post-demo.** App Runner is
> effectively in maintenance mode (no meaningful new features). Treat the current
> App Runner setup as **demo-only**; **after the demo, move both services (theme +
> video) to Amazon ECS Express Mode** (or equivalent). The migration is mostly a
> lift-and-shift of the same ECR images — the runtime env vars documented below
> (e.g. VideoService `DATABASE_URL`) carry over as the new platform's
> service/task environment; same principle, different console.

## Resources

| Thing | Value |
|---|---|
| ECR (theme) | `259645229668.dkr.ecr.us-east-1.amazonaws.com/combatden-themeservice:latest` |
| ECR (video) | `259645229668.dkr.ecr.us-east-1.amazonaws.com/combatden-videoservice:latest` |
| App Runner theme ARN | `arn:aws:apprunner:us-east-1:259645229668:service/combatden-themeservice/8db0e7b19c8b4a9d9c952489e84809e1` |
| App Runner video ARN | `arn:aws:apprunner:us-east-1:259645229668:service/combatden-videoservice/e86bea56dcdd4b6d8f71af2fe61dbf4c` |
| App Runner theme URL | `https://abibsptdpz.us-east-1.awsapprunner.com` |
| App Runner video URL | `https://nipsan8msq.us-east-1.awsapprunner.com` |
| Auto-scaling cap | `combatden-cap1` (min=1, max=1 — hard cost cap) |
| ECR-access role | `AppRunnerECRAccessRole` |
| S3 bucket (app) | `combatden-app` |
| ACM cert (app) | `arn:aws:acm:us-east-1:259645229668:certificate/e03eba9c-0d77-4714-aa38-02dbcddb7146` |
| Budget | `combatden-demo-monthly` ($30/mo, alerts → jesse@combatden.net) |

## DNS records to add at Squarespace (Host = the part before `combatden.net`)

**Round 1 — add all 7 now.** App Runner certs + the API aliases + the app cert
validation. (Values keep their trailing dot; Squarespace accepts that.)

| Host | Type | Value | Purpose |
|---|---|---|---|
| `theme` | CNAME | `abibsptdpz.us-east-1.awsapprunner.com` | theme API alias |
| `_46c9650c4618b9dd8594743d89809f09.theme` | CNAME | `_d751d0ddc9ada052a33cd23425b0f56d.jkddzztszm.acm-validations.aws.` | theme cert |
| `_60eb3444bf9c4e6ecbc495aa35adf739.zvdsn94ksdwhlw07rfudmk4c3wanccq.theme` | CNAME | `_87b4beebfb46af8e0bdd6ea859a4f1a6.jkddzztszm.acm-validations.aws.` | theme cert |
| `video` | CNAME | `nipsan8msq.us-east-1.awsapprunner.com` | video API alias |
| `_83051f7059786c75986189a34349a7d2.video` | CNAME | `_69534f170cdeaf989d2edd2f60a5b0f9.jkddzztszm.acm-validations.aws.` | video cert |
| `_7febc7bb3a32b203d0a2a17b73f88c9a.v2oojtw79b2yi1waxwikhwlpin718dp.video` | CNAME | `_ca4f46431c042bfbb38438f7011f3784.jkddzztszm.acm-validations.aws.` | video cert |
| `_91b680de3115db41fa72cc11a871c61b.app` | CNAME | `_7b77e279101c69a919272b98b94418da.jkddzztszm.acm-validations.aws.` | app cert |

**Round 2 — after the app cert validates and `make deploy-finalize` runs**, it
prints one more record:

| Host | Type | Value |
|---|---|---|
| `app` | CNAME | `<the CloudFront domain finalize prints>` |

## Deploy / redeploy

**APIs** (after editing code or assets):
```
cd ThemeService   # or VideoService
docker build -t combatden-themeservice:latest .
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 259645229668.dkr.ecr.us-east-1.amazonaws.com
docker tag combatden-themeservice:latest 259645229668.dkr.ecr.us-east-1.amazonaws.com/combatden-themeservice:latest
docker push 259645229668.dkr.ecr.us-east-1.amazonaws.com/combatden-themeservice:latest
aws apprunner start-deployment --region us-east-1 --service-arn <theme ARN>   # AutoDeployments are off
```

### VideoService runtime config — `DATABASE_URL` (App Runner env var, NOT in the image)

VideoService no longer bakes data into the image; it **reads the shared Supabase
Postgres at runtime**, so its container needs `DATABASE_URL`. (ThemeService
already uses this same App Runner env-var pattern for `GOOGLE_FONTS_API_KEY`, and
now `ASSETS_CDN_BASE_URL` too — see the assets section below.) The rule:

- **Never copy `.env` into the image / `Dockerfile`.** That bakes the DB password
  into an ECR layer, and the local `.env` points at `127.0.0.1` — the prod
  container would try to reach localhost. The image stays env-agnostic (`src/` +
  `schema/` only).
- Set `DATABASE_URL` as a **runtime environment variable on the App Runner
  service** (one-time; it persists across `start-deployment` redeploys). Pydantic
  reads it straight from the environment — no `.env` file in the container.
  - Console: video service → Configuration → Edit → *Environment variables* →
    `DATABASE_URL = postgresql://...@db.rgmvgevwclvqhjeirzfb.supabase.co:5432/postgres`
    (raw `postgresql://` is fine — `src/shared/database.py` normalises it to asyncpg).
  - CLI: `aws apprunner update-service --service-arn <video ARN> --source-configuration 'ImageRepository={ImageConfiguration={RuntimeEnvironmentVariables={DATABASE_URL=postgresql://...}}}'`
- **Preferred for the secret:** store the URL in AWS Secrets Manager / SSM and
  reference it via App Runner `RuntimeEnvironmentSecrets` (ARN), so the password
  isn't sitting in the service config either.
- After setting it, redeploy as above. Without it the container starts but 500s
  on the first query.

**Schema + data on prod** (run from your machine, never baked/automated):
- Schema: applied via Supabase migrations from `Database/` (you run them). **Never
  `supabase db pull` while local schema is ahead of prod** — it generates a
  destructive migration that drops the new tables.
- Content: load/refresh the prod DB with the pipeline pointed at prod via the
  `ENV_FILE` flag — `ENV_FILE=.env.prod make sync-gyms-prod GYM_ID=all` then
  `make import-yaml-prod` (prod secrets live in the gitignored `VideoService/.env.prod`).

### ThemeService assets — S3 + CloudFront (`cdn.combatden.net`)

ThemeService images/icons are served from CloudFront, not the container (the
Dockerfile no longer bakes the ~2.6 GB — only `output.yaml` metadata). One-time
provision via `ThemeService/deploy-assets/` (boto3, its own isolated venv — no
uvloop; mirrors `CRM/deploy/`):

```bash
cd ThemeService
make assets-install      # boto3-only venv in deploy-assets/
make assets-provision    # ensures bucket (private) + ACM cert → prints validation CNAME
#   add the printed CNAME at Squarespace, wait ~5 min for the cert to validate
make assets-finalize     # OAC + cache policy (keyed on ?v=) + CORS headers + CloudFront → prints the cdn CNAME
#   add the cdn CNAME, wait for the distribution to Deploy (~5 min)
```

The scripts get right the three things that are easy to botch by hand:
- **OAC** — private bucket, readable only by this CloudFront distribution (Block
  Public Access stays ON; no public bucket). This is also why you can't hand the
  client a raw `…s3.amazonaws.com/…` URL — the bucket returns 403; CloudFront is
  the only public read path.
- **A custom cache policy keyed on `v`** — AWS's managed CachingOptimized policy
  *ignores* query strings, so regenerated `?v=<hash>` images would serve stale.
  `finalize.py` creates a policy that includes `v` in the cache key. (This is why
  we kept `?v=` instead of versioned filenames.)
- **A CORS response-headers policy (`Access-Control-Allow-Origin: *`)** — the
  clients are Flutter **web** apps (admin + theme browser) whose CanvasKit
  renderer *fetches* each image via XHR and decodes the bytes; the browser blocks
  that cross-origin unless the response carries a CORS header. The images live on
  a different origin (`cdn.combatden.net`) than the apps, so without this every
  card shows a broken-image placeholder **even though the PNG returns 200**.
  `finalize.py` attaches the header at the edge (applied on cache hits too — no
  invalidation needed). This is NOT specific to CloudFront: any cross-origin image
  host (raw S3 included) needs it; the only CORS-free option is same-origin
  serving, which is the slow container path we left.

> **Re-running `make assets-finalize` is safe and is how you patch a live CDN.**
> It reuses the existing bucket/cert/distribution and only ensures the OAC, cache
> policy, and CORS policy are attached (idempotent). The CORS policy was added
> after the distribution already existed, so a re-run is exactly what wires it
> into the running distribution without recreating it.

No SPA 403/404→index rewrite — it's an asset CDN; a missing key should 404.

> **DNS Host field is base-domain-relative.** Squarespace auto-appends
> `combatden.net` to the Host, so the scripts print the host **without** it (e.g.
> `_1ed0…cdn`, or `cdn`) — paste exactly that. Do **not** add `.combatden.net`
> yourself or it doubles (`…cdn.combatden.net.combatden.net`). The Value
> (cert target / CloudFront domain) keeps its full form + trailing dot.

Then:
- `ASSETS_CDN_BASE_URL` is **no longer required as an env var** — both services
  default it to `https://cdn.combatden.net` in code (ThemeService
  `src/api/config.py`, VideoService `src/api/config.py`), so they always emit
  absolute CDN URLs (theme: image/icon URLs)
  even when the App Runner var is unset. Only set it to point at a *different*
  CDN; set it empty for local serving. (This replaced the earlier "must be set
  in prod or paths 404" requirement — the de-baked container can't serve the
  bytes, so CDN is now the safe default rather than an opt-in.)
- Backfill: from `ThemeService/`, with AWS creds configured, run `make sync-assets`
  (~760 PNG + 304 SVG, skips unchanged). The bucket name defaults to
  `combatden-assets` (override via `ASSETS_BUCKET` only if it ever changes). Needs
  boto3 installed (`poetry install` on a machine that can build uvloop).
- New theme runs self-upload when `ASSET_UPLOAD_ENABLED=1` in the pipeline env;
  `make sync-assets` is the always-available backstop.
- Then `make ecr-push` (ThemeService) to ship the de-baked image. **No Flutter
  change needed** — the clients render whatever URL the API returns.

**App** (from `CRM/`): `make deploy-provision` → add app cert record →
`make deploy-finalize` → add the `app` CNAME → `make deploy` (build + upload +
invalidate). Day-to-day after setup: just `make deploy`.

**Theme browser** (from `CRM/`, tooling in `deploy-themes/`): same
flow, own bucket/domain — `make deploy-themes-install` → `make
deploy-themes-provision` → add the `themes` cert record → `make
deploy-themes-finalize` → add the `themes` CNAME → `make deploy-themes` (build
the theme-browser target + upload + invalidate). Day-to-day: just `make
deploy-themes`. Note both targets build into `build/web`, so run admin and
themes deploys one at a time.

## Combined backend + worker image (`deploy/`)

A separate deployment target from the demo App Runner services above: **one Docker
image that runs the FastApiBackend API and the VideoService background worker
together** (`deploy/Dockerfile` + `deploy/entrypoint.sh`). This is the production
path for the CRM's backend + the video pipeline — it does **not** replace the
ThemeService / VideoService read APIs, which stay on App Runner (the VideoService
read API keeps serving the MobileApp until it's repointed).

**What runs inside** (exactly two processes, supervised by `entrypoint.sh`):
1. **FastApiBackend** — `uvicorn src.main:app` on `:8000` (the CRM-facing API).
2. **VideoService worker** — `python -m src.worker.run`, a background loop that pops
   the `video_worker_queue` and regenerates gym feeds (no listening port).

Each app installs into its own poetry venv inside the image (the two projects pin
different fastapi/uvicorn versions). If either process exits, the container exits
nonzero so the platform restarts it (a half-alive container is a silent outage).

**Build** — context is the **monorepo root**, not `deploy/` (the image needs
`FastApiBackend/`, `VideoService/`, and `Database/python_data/schema/` as siblings):
```
docker build -f deploy/Dockerfile -t combatden-backend-worker .
```

**Platform — always-on, NOT App Runner.** The worker must keep running between
requests, so this image targets an **always-on service (Amazon ECS Express Mode
direction)**. App Runner's CPU throttling on scale-to-idle would starve the
background worker. The Dockerfile itself is platform-agnostic.

**Runtime env vars** — none are baked into the image; the platform injects them at
container start. The authoritative list (names only) lives in **`deploy/CLAUDE.md`**:
the FastApiBackend Supabase / Stripe / `DATABASE_URL` / LLM keys plus the worker's
`DATABASE_URL` / `APIFY_TOKEN` / `GEMINI_API_KEY` / `OPENAI_API_KEY`, cross-checked
against each app's `src/core/config.py` and `.env.example`.

## Demo on / off (pause posture)

Pause both between demos to zero out compute billing; resume (~1 min) before:
```
# down (after a demo)
aws apprunner pause-service  --region us-east-1 --service-arn <theme ARN>
aws apprunner pause-service  --region us-east-1 --service-arn <video ARN>
# up (before a demo)
aws apprunner resume-service --region us-east-1 --service-arn <theme ARN>
aws apprunner resume-service --region us-east-1 --service-arn <video ARN>
```
Pausing keeps the image, service, custom domain, and cert intact — going to
real prod just means not pausing. (See `ThemeService`/`VideoService` Makefile
`pause`/`resume` targets.)
