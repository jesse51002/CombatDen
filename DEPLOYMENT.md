# CombatDen — Production Deployment (demo)

First production deployment. A live, public, HTTPS demo of the gym-owner admin
app backed by its two read-only APIs, on `combatden.net`. AWS account
`259645229668`, region `us-east-1`. DNS is manual at **Squarespace**.

```
app.combatden.net     → CloudFront → S3 (combatden-app)         static Flutter build/web
themes.combatden.net  → CloudFront → S3 (combatden-themes)      static Flutter build/web (theme browser)
theme.combatden.net   → App Runner → ECR combatden-themeservice  uvicorn :8000  (apps/ 2.6GB)
video.combatden.net   → App Runner → ECR combatden-videoservice  uvicorn :8002  (gyms/+videos/)
```

`themes.combatden.net` is the **public theme browser** — a second build target of
the same `AppManagement/` Flutter project (`--target lib/main_theme_browser.dart`),
not a separate app. It hits the same two read-only APIs. The marketing landing
page just links to it (and it links back). See `AppManagement/CLAUDE.md`
→ *Standalone theme browser*.

The app build bakes in the two API URLs via `--dart-define` (CUST_BASE_URL,
VIDEO_BASE_URL). CORS on both APIs is `["*"]`; both are GET-only, no auth.

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

**App** (from `AppManagement/`): `make deploy-provision` → add app cert record →
`make deploy-finalize` → add the `app` CNAME → `make deploy` (build + upload +
invalidate). Day-to-day after setup: just `make deploy`.

**Theme browser** (from `AppManagement/`, tooling in `deploy-themes/`): same
flow, own bucket/domain — `make deploy-themes-install` → `make
deploy-themes-provision` → add the `themes` cert record → `make
deploy-themes-finalize` → add the `themes` CNAME → `make deploy-themes` (build
the theme-browser target + upload + invalidate). Day-to-day: just `make
deploy-themes`. Note both targets build into `build/web`, so run admin and
themes deploys one at a time.

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
