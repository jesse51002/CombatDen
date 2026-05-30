# Scrape (fetch + classify the pool)

Fill and refresh the **shared video pool** (`VideoService/videos/`). This guide
is **only** about the scraper. It does not author gyms (a gym already exists with
`queries` — see `gym_maker.md`) and it does not approve videos for any gym
(that's the scan — see `scan.md`). The scraper produces a **gym-agnostic** pool;
tagging here is content classification, never approval.

## What it does, in one pass

`scripts/scraper` does fetch **and** classify in one run:

1. **Gather queries** — reads every gym's `videos.queries` (or one gym's, with
   `--gym-id`) and unions them. The gyms own the searches; the scraper just
   collects them.
2. **Fetch from Apify** — one actor (`streamers/youtube-scraper`) does the search
   + metadata + channel avatar + the transcript inline (`subtitlesFormat=plaintext`),
   so search and transcript are the same step. Results are de-duplicated across
   queries; each kept video records its `source_queries` and a `relevance_index`.
3. **Classify** — an LLM reads each video's title / description / transcript and
   writes two independent axes onto the pooled record:
   - `tag` — the single genre (`VideoType`).
   - `gym_type` — the **list** of disciplines the content fits (e.g.
     `[kettlebell, rowing]`). This is what routes a video into the candidate
     slices gyms scan. It is **content classification, not approval** — a video
     tagged `vinyasa` is merely a *candidate* for vinyasa gyms; whether it's good
     is decided per-gym by the scan.

The result is `videos/<video_id>.yaml`, one file per video, no manifest wrapper.

## Run it

```bash
make scrape                 # every gym's queries → pool, then classify
make scrape GYM_ID=vinyasa  # only the vinyasa gym's queries
```

(Equivalently `poetry run python -m scripts.scraper.run [--gym-id <id>]`. Always
`poetry run`, never bare `python3` / `.venv/bin/*`.)

## Cost, idempotency, env

- **Apify** bills per result (~$2.40 / 1000 videos). The transcript rides along in
  the same call, so there's no separate transcript spend.
- **LLM** tagging is cheap per video but real — it's a model call per video.
- A scrape **appends two `CostEntry`s** to `cost_log.yaml`: one `SEARCH` (Apify
  spend) and one `TAG` (LLM spend), each with its breakdown.
- Env: `APIFY_TOKEN` (fetch) and the tagging model key (e.g. `GEMINI_API_KEY`) in
  `.env`.

## Sequential only

Per project rule (`[[feedback_aicust_generations_sequential]]`): **one pipeline
run in flight at a time** — providers are rate-limited. Never launch a scrape in
parallel with another scrape or a scan. Let one finish before starting the next.

## Boundaries

- The scraper never writes gym files and never touches any gym's
  `good_video_ids` / `rejected_video_ids` / `scan_costs`.
- It writes only the pool (`videos/`) and the `cost_log.yaml`.
- After a scrape, run the **scan** (`scan.md`) to turn the freshly-tagged pool
  into each gym's curated feed.
