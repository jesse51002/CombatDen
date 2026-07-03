---
name: videoservice
description: >-
  Operate VideoService — the single-tenant, gym-centric video system. The gym is
  the unit: VideoService/gyms/<gym_id>.yaml holds a gym's disciplines (gym_type),
  its chosen theme (a ThemeService design id), its video config (specification +
  search queries), and optional classes + rewards. All machine state lives in the
  shared Supabase Postgres video_* tables — the shared pool, each gym's curated
  feed (video runs), per-video RAG summaries/embeddings (video_rag), and the spend
  ledger. Two kinds of work: (1) GYM AUTHORING — author/edit a gym file
  (references/gym_maker.md), then load it into SQL with make sync-gyms; and (2) THE
  BACKGROUND WORKER — the automated scrape -> funnel -> enrich -> scan ->
  feed-write pipeline that regenerates a gym's feed and builds the RAG layer,
  triggered by the FastApiBackend through the video_worker_queue
  (references/scraper.md = the ingest half, references/scan.md = the judgment
  half). Use this skill whenever the user wants to set up a gym, write a gym's
  videos config / classes / rewards, run make sync-gyms, or understand / run /
  debug the video worker. Trigger on anything gym-file / video-pool / scrape /
  funnel / enrich / scan / feed / worker shaped for VideoService.
---

# VideoService — gyms, the pool, and the worker

VideoService is **single-tenant and gym-centric**. Each gym's hand-authored config
is git-tracked YAML; everything machine-generated lives in the shared Supabase
Postgres `video_*` tables:

```
gyms/<gym_id>.yaml   a gym: gym_type (disciplines) + theme (design id) +
                     videos {specification, queries} + classes + rewards
video_* (Postgres)   the shared pool (video), each gym's curated feed (video_run +
                     gym_video_feed), per-video RAG (video_rag = summary +
                     embedding), and the spend ledger (video_cost_log)
```

The gym files are loaded into SQL with `make sync-gyms`. There is **no `apps/`
layer, no tenant id, no manifest**. The theme→gym link is just the gym's `theme`
field (one ThemeService design id). The gym browser derives a coarse
`parent_gym_type` (Fighting / Yoga / …) from the primary discipline.

## The two kinds of work — load only the guide you need

| You want to… | Read | How it runs |
| --- | --- | --- |
| Author or edit a **gym** (its config, classes, rewards) | `references/gym_maker.md` | `scripts/gym_maker` (operator: `make gym-check`), then `make sync-gyms` |
| Understand / run / debug the worker's **ingest** (scrape → funnel → enrich) | `references/scraper.md` | `src/worker` (`make worker`), backend-triggered |
| Understand / run / debug the worker's **judgment** (scan → feed-write) | `references/scan.md` | `src/worker` (`make worker`), backend-triggered |

**Gym authoring is the one operator-driven job.** The scrape/scan pipeline is no
longer a per-step script — it is the single background **worker** (`src/worker`,
`python -m src.worker.run`), which the FastApiBackend enqueues per gym on the
Postgres `video_worker_queue` and which runs the whole pipeline under a global
lock. `make worker` runs it locally against `.env`. (The old `scripts/scraper` +
`scripts/scan` + `src/classification` are deleted — the worker absorbed them.)

## How the pieces connect

1. **Author a gym** — `gyms/<id>.yaml`: disciplines + theme + `videos.specification`
   (the keep/avoid criteria) + `videos.queries` (the searches) + optional
   classes/rewards. (Feed/verdicts are machine state — the worker fills them.)
2. **Sync → SQL** — `make sync-gyms` upserts the gym + loads the existing pool/feeds.
3. **The worker runs** — when the backend enqueues the gym (spec save or manual
   run), or `make worker` locally: scrape the queries into the shared `video` pool
   → funnel candidates (query-overlap Tier 1 + RAG-probe Tier 2) → enrich each with
   a multimodal summary + embedding into `video_rag` → scan keep/drop against the
   spec → write the gym's new feed run with owner-curation carry-forward.

## The worker vs the FastApiBackend (who owns what)

- **VideoService owns the worker** (`src/worker`) — the *execution*.
- **FastApiBackend owns the control surface** — it enqueues `video_worker_queue`
  (on every spec save, and the manual `POST …/video-worker/run` route), exposes
  worker status, serves the feed, and serves the RAG member-recs + semantic search
  that the worker's `video_rag` rows power. The two never call each other — the
  queue + the `video_*` tables are the hand-off. The embedding model +
  `vector(1536)` dimension is a contract pinned on both sides.

## Hard rules (all work)

- **No assumptions** (`CLAUDE.md`): when a decision has more than one reasonable
  answer, ask and wait — present researched options, never pick for the user.
- **One question per turn**, multiple-choice by default (see `gym_maker.md`).
- **Validate before writing** any gym file against the `Gym` model via
  `poetry run` (never bare `python3` / `.venv/bin/*`).
- The worker processes **one gym at a time** under its global lock; within a gym,
  provider calls fan out only to the configured `worker_*_concurrency`. Never
  bypass the lock or parallelize runs.
