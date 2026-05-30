# Scan (curate a gym's feed)

Turn the shared pool into one gym's feed. This is a **thin** job — you run a
command. It does not author gyms and does not fetch or tag videos (those are
`gym_maker.md` and `scraper.md`). It needs a gym that already has a
`specification`, and a pool that's already been scraped + classified.

## Run it

```bash
make scan GYM_ID=vinyasa   # scan one gym
make scan GYM_ID=all       # scan every gym
```

(Equivalently `poetry run python -m scripts.scan.run --gym-id <id>` /
`--all-gyms`. Always `poetry run`.)

## What it does

For each scanned gym: take the pool slice tagged with the gym's `gym_type`(s),
judge each candidate against the gym's `videos.specification` (an LLM call), and
write the verdicts back onto the gym.

- **Overwrites** `good_video_ids` and `rejected_video_ids` every run — a scan is
  a fresh verdict, not an append. (Re-running re-decides from scratch.)
- **Appends** one `ScanCost {at, usd}` to the gym's `scan_costs` history per run.
- **Appends** one `SCAN` `CostEntry` to `cost_log.yaml` for the whole run.

Only `good_video_ids` is ever served (the gym's feed); the rejected list and the
raw pool are never sent to the user.

## Before you scan

- The gym exists and has a `specification` (`gym_maker.md`).
- The pool is scraped and classified, so candidates carry `gym_type`
  (`scraper.md`). A gym with no matching tagged videos scans to an empty feed.

## Sequential only

Per project rule (`[[feedback_aicust_generations_sequential]]`): one run in
flight. Don't scan in parallel with a scrape or another scan.
