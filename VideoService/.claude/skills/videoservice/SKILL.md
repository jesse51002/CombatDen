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
  BACKGROUND WORKER — DECOUPLED, DB-backed steps, not a per-gym pipeline: every
  tick runs cleanup + finalize for free, then drains ONE heavy step, first-with-work
  (scan, else enrich, else scrape — scrape is the only quota-bound, per-gym,
  run-opening step; enrich and scan are global gym-agnostic sweeps that build the
  RAG layer and settle feed verdicts), a self-scheduling design with no job queue
  and no FastApiBackend trigger (references/scraper.md = the tick + the scrape
  step, references/scan.md = enrich + scan + finalize). Use this skill whenever
  the user wants to set up a gym, write a gym's videos config / classes / rewards,
  run make sync-gyms, or understand / run / debug the video worker. Trigger on
  anything gym-file / video-pool / scrape / funnel / enrich / scan / feed / worker
  shaped for VideoService.
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
                     embedding), and the generic spend ledger (cost_log,
                     source='video')
```

The gym files are loaded into SQL with `make sync-gyms`. There is **no `apps/`
layer, no tenant id, no manifest**. The theme→gym link is just the gym's `theme`
field (one ThemeService design id). The gym browser derives a coarse
`parent_gym_type` (Fighting / Yoga / …) from the primary discipline.

## The two kinds of work — load only the guide you need

| You want to… | Read | How it runs |
| --- | --- | --- |
| Author or edit a **gym** (its config, classes, rewards) | `references/gym_maker.md` | `scripts/gym_maker` (operator: `make gym-check`), then `make sync-gyms` |
| Understand / run / debug the worker's **tick + ingest** (cleanup → finalize → the scrape step) | `references/scraper.md` | `src/worker` (`make worker`), self-scheduling |
| Understand / run / debug the worker's **judgment + RAG build** (enrich → scan) | `references/scan.md` | `src/worker` (`make worker`), self-scheduling |

**Gym authoring is the one operator-driven job.** The scrape/enrich/scan work runs
as the single background **worker** (`src/worker`, `python -m src.worker.run`) — a
loop of DECOUPLED, DB-backed steps, not a per-gym pipeline. Every tick runs cleanup
(strike-maxed video deletion) + finalize (complete/fail `running` runs from their
feed rows) for free, then drains ONE heavy step, first-with-work: **scan** (a
global multimodal verdict sweep), else **enrich** (a global RAG-building sweep),
else **scrape** (the only quota-bound, per-gym, run-opening step — it alone still
derives its due gym from timestamps already in the schema: a fresh `admin_update`
spec version, a settled manual feed curation, or a weekly refresh floor). `make
worker` runs the loop locally against `.env`.

## How the pieces connect

1. **Author a gym** — `gyms/<id>.yaml`: disciplines + theme + `videos.specification`
   (the keep/avoid criteria) + `videos.queries` (the searches) + optional
   classes/rewards. (Feed/verdicts are machine state — the worker fills them.)
2. **Sync → SQL** — `make sync-gyms` upserts the gym + loads the existing pool/feeds
   **and the template RAG sidecar** (`video_rag/video_rag.jsonl` → `video_rag`), so
   imported preset feeds serve instantly instead of waiting for the worker to
   enrich. That sidecar is built once by the PAID `make enrich-templates` run
   (enriches the ~18.9k unique `template_gym_feed` videos, reusing
   `WorkerEnricher.enrich_one`; untracked-local like `videos/`, ~330 MB, S3 to
   prod). See the CLAUDE.md "Jobs / workflow" for the full flow.
3. **The worker runs** — its tick is three DECOUPLED DB-backed steps, not a single
   per-gym pipeline: cleanup + finalize run every tick for free, then ONE heavy
   step, first-with-work, is drained fully — **scan** judges each gym's `pending`
   feed rows (written by a prior scrape) against that gym's LATEST spec, else
   **enrich** gives every un-enriched video across every gym ONE multimodal
   summary + embedding into `video_rag`, else **scrape** picks the next due gym,
   fetches its queries into the shared `video` pool, funnels candidates
   (query-overlap Tier 1 + RAG-probe Tier 2), and writes them as `pending` feed
   rows with owner-curation carry-forward from the prior completed run.

## The worker vs the FastApiBackend (who owns what)

- **VideoService owns the worker** (`src/worker`) — the *execution*, fully
  self-scheduling.
- **FastApiBackend has NO worker-control surface at all** — not even a read-only
  status endpoint; there is nothing to enqueue and no manual-run route. It only
  *reads* the shared tables the worker writes: the **unified feed**
  (`GET /gyms/{id}/videos` — merges the owner section with the gym's latest
  COMPLETED run, serves only enriched-AND-accepted videos, optionally personalized
  to a member's taste embedding), the **separate ungated owner-management listing**
  (`GET /gyms/{id}/videos/owner` — shows an owner-added video before it's
  enriched), and the RAG member recommendations — a single rotating-category rec
  per request, itself a thin wrapper over the unified feed — that the worker's
  `video_rag` rows power. The two never call each other — the shared `video_*`
  tables (and their timestamps) are the hand-off the worker reads to derive its own
  work. The embedding model + `vector(3072)` dimension is a contract pinned on both
  sides.

## Hard rules (all work)

- **No assumptions** (`CLAUDE.md`): when a decision has more than one reasonable
  answer, ask and wait — present researched options, never pick for the user.
- **One question per turn**, multiple-choice by default (see `gym_maker.md`).
- **Validate before writing** any gym file against the `Gym` model via
  `poetry run` (never bare `python3` / `.venv/bin/*`).
- The worker's tick is single-threaded end-to-end under its global lock — only
  one worker instance ticks at a time. The **scrape** step still processes one gym
  at a time (its due-gym selection); **enrich** and **scan** are global sweeps that
  touch many gyms' videos within one tick. Within any step, provider calls fan out
  only to the configured `worker_*_concurrency`. Never bypass the lock or run two
  workers concurrently.
