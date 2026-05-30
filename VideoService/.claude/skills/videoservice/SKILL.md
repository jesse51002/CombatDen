---
name: videoservice
description: >-
  Operate the single-tenant, gym-centric VideoService. The gym is the unit:
  VideoService/gyms/<gym_id>.yaml holds a gym's disciplines (gym_type), its
  chosen theme (a ThemeService design id), its video config (specification +
  search queries), its scan-curated feed (good/rejected video ids + scan_costs),
  and optional classes + rewards cards. A shared video pool lives flat at
  VideoService/videos/, and spend is logged to VideoService/cost_log.yaml. There
  are exactly three jobs, each with its own focused guide — load ONLY the one you
  need: (1) MAKE A GYM — author/edit a gym file (references/gym_maker.md); (2)
  SCRAPE — fetch videos from Apify into the pool AND classify them with gym_type
  + genre tags (references/scraper.md); (3) SCAN — run the per-gym keep/drop scan
  that fills each gym's good/rejected feed (references/scan.md). Use this skill
  whenever the user wants to set up a gym, write/edit a gym's videos config or
  classes/rewards, run the scrape/classify, or run a scan. Trigger on anything
  gym-file / video-pool / scrape / classify / scan shaped for VideoService.
---

# VideoService — gyms, the pool, and the pipeline

VideoService is **single-tenant and gym-centric**. Everything is flat under
`VideoService/`:

```
gyms/<gym_id>.yaml      a gym: gym_type (disciplines) + theme (design id) +
                        videos {specification, queries, good_video_ids,
                        rejected_video_ids, scan_costs} + classes + rewards
videos/<video_id>.yaml  the shared video pool (no manifest wrapper)
cost_log.yaml           append-only spend ledger (one entry per pipeline run)
```

There is **no `apps/` layer, no tenant id, no manifest**. The theme→gym link is
just the gym's `theme` field (each gym names one ThemeService design id). The
gym-browser API derives a coarse `parent_gym_type` (Fighting / Yoga / … ) from
the gym's primary discipline for the picker's filter.

## The three jobs — load only the guide you need

This skill is deliberately split so each concern stays clean. Read the matching
file and **ignore the others**:

| You want to… | Read | Script |
| --- | --- | --- |
| Author or edit a **gym** (its config, classes, rewards) | `references/gym_maker.md` | `scripts/gym_maker` |
| **Scrape** videos into the pool **and classify** them (gym_type + genre tags) | `references/scraper.md` | `scripts/scraper` |
| **Scan** a gym → fill its good/rejected feed | `references/scan.md` | `scripts/scan` |

The natural order is **make a gym → scrape → scan**, but they're independent:
the gym maker never scrapes or scans, the scraper never makes gyms, and scan is
a thin command runner.

## How the pieces connect (just enough to orient)

1. **Make a gym** — author `gyms/<id>.yaml`: pick the discipline(s) and the theme
   it runs, write its `videos.specification` (what to keep/avoid — the scan's
   criteria) and `videos.queries` (the searches that feed it), plus optional
   `classes`/`rewards`. (`good_video_ids`/`rejected_video_ids`/`scan_costs` start
   empty — the pipeline fills them.)
2. **Scrape** — gather every gym's `videos.queries`, fetch from Apify into the
   shared pool (`videos/`), and tag each pooled video with `gym_type` (the
   disciplines it fits) + a genre. The pool is gym-agnostic; tagging is content
   based, never approval.
3. **Scan** — for one gym (or all), judge the pool slice matching the gym's
   disciplines against the gym's `specification`, and write the gym's
   `good_video_ids` (its feed) / `rejected_video_ids`. **Scan overwrites** the
   good/rejected lists each run (fresh verdicts) and **appends** a `ScanCost` to
   the gym's `scan_costs` history.

Spend from scrape + scan is appended to `cost_log.yaml` (an `ExecutionType` +
a cost breakdown per entry).

## Hard rules (all three jobs)

- **No assumptions** (`CLAUDE.md`): when a decision has more than one reasonable
  answer, ask and wait — present researched options, never pick for the user.
- **One question per turn**, multiple-choice by default (see `gym_maker.md`).
- **Validate before writing** any gym file against the `Gym` model via
  `poetry run` (never bare `python3` / `.venv/bin/*`).
- Keep each job's context separate — don't drag scraping detail into gym
  authoring, or vice versa.
