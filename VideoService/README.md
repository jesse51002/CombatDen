# Video Service

A lightweight, **temporary** demo service for a YouTube query system. Per company
it captures a `videos_config.yaml` brief — the business, the *kinds* of YouTube
videos worth surfacing, what to avoid, and a curated list of **10–20 search
prompts** spanning the full content spectrum (entertainment → educational →
informative → vlog → professional → clips → fun), each tagged with one or more
`VideoType` genres.

Three pieces:

- **`video-brief` skill** (`.claude/skills/video-brief/`) — the single end-to-end
  pipeline: a lean, question-driven interview authors `videos_config.yaml`, then it
  offers (each opt-in) to **fetch** the videos, **audit** them (remove anti-gym
  content), and generate the four branded **class cards** (`class_output.yaml`).
- **YouTube batch script** (`scripts/youtube_batch/`) — runs a brief's searches
  against the YouTube Data API v3 and writes `apps/<app_id>/videos_output.yaml`.
  Manual, run on demand. See [Run the searches](#run-the-searches).
- **Read-only API** (`src/api/`) — serves the validated brief and its search
  list, company-keyed. Modelled on CustomizationService's output API.

The schema is expected to fold into `../FastApiBackend/` eventually; it's kept
separate now for speed.

## Architecture (high level)

The pipeline turns a company's intent into a concrete, cached list of videos —
authored once, queried occasionally, read constantly:

```
                 author                  query (manual)            read
  human ──▶ video-brief skill ──▶ scripts/youtube_batch ──▶ apps/<id>/videos_output.yaml
                  │                        │                         │
                  ▼                        ▼                         ▼
       apps/<id>/videos_config.yaml   YouTube Data API        mobile app / clients
       (brief: 10–20 tagged searches)   (search + enrich)     (group by genre tag)
```

1. **Author** — the skill interviews a gym owner and writes `videos_config.yaml`:
   the business, what videos to surface/avoid, and 10–20 search prompts each
   tagged with one or more of the 12 `VideoType` genres.
2. **Query** — the batch script reads that brief, runs each search against
   YouTube, enriches results (creator pfp, view/like counts), de-duplicates
   videos that surface from multiple searches (unioning their genre tags), and
   writes `videos_output.yaml`. **This is the only component that touches the
   YouTube API**, and its output is a cache — the API is hit once per query, not
   per app open.
3. **Read** — clients (the mobile app, the read-only API) consume the cached
   output and group videos by their `tags` for the genre-based feed. They never
   call YouTube, so end users consume **zero** API quota.

`schema/` is the shared contract across all three: `VideosConfig`/`VideoSearch`
(the brief) and `VideosOutput`/`VideoOutput` (the result).

## Run the API

```bash
poetry install
make api          # uvicorn on http://localhost:8002
```

Endpoints (read-only):

| Method & path | Returns |
|---|---|
| `GET /health` | liveness probe |
| `GET /apps` | company ids that have a `videos_config.yaml` |
| `GET /apps/{app_id}` | the full validated `VideosConfig` (the brief) |
| `GET /apps/{app_id}/searches` | the search list; optional `?video_type=<enum>` filter |
| `GET /apps/{app_id}/videos` | the **fetched videos** (`VideosFeed`); optional `?video_type=<enum>` filter. `404` until the batch script has produced a `videos_output.yaml` |
| `GET /apps/{app_id}/classes` | the **4 branded class cards** (`ClassOutput`). `404` until the class-images step has produced a `class_output.yaml` |

`GET /apps/{app_id}/videos` serves a **slim, frontend-only** projection of
`videos_output.yaml`: per video it returns `url`, `title`, `thumbnail_url`,
`channel_name`, `channel_url`, `channel_avatar_url`, `view_count`,
`relevance_index`, `tags`, and `big_groups`. The validation-only fields
(`description`, `like_count`, `source_queries`) and run accounting
(`quota_units_estimate`) stay in the file but are **not** sent over the wire.

`relevance_index` is the video's best (lowest) position across the searches that
surfaced it — `0` is the top hit, lower is more relevant — for the frontend to
sort within a group.

`big_groups` is the **primary frontend sort**: the coarse `educational` /
`entertainment` split derived from a video's `tags`. Only `educational`,
`tutorial`, and `informative` map to `educational`; every other genre maps to
`entertainment`. A video whose tags span both is in both groups, so it's a
list. (See `schema/big_group.py`.)

Interactive docs at `http://localhost:8002/docs`.

## Author a brief

Invoke the `video-brief` skill (e.g. "set up youtube searches for a new
company"). It interviews you, drafts 10–20 tagged search prompts, validates
against the `VideosConfig` model, and writes `apps/<app_id>/videos_config.yaml`.

## Run the searches

Runs a brief's searches against the YouTube Data API v3 and writes
`apps/<app_id>/videos_output.yaml`. Manual — run it when a brief changes, not on
a schedule.

```bash
# one-time: put a key in .env (Google Cloud project with YouTube Data API v3 on)
echo "YOUTUBE_API_KEY=..." >> .env

make youtube APP_ID=combatden

# cheapest real end-to-end check — the one-search apps/smoketest brief (~100 units)
make smoke
```

Each video in the output carries the **genre tags** of every search that
surfaced it (videos found by multiple searches are de-duplicated, their tags
merged) — that's the grouping key for the genre feed.

```yaml
company_name: Killer Muay Thai
app_id: combatden
generated_at: 2026-05-21T18:04:11Z
quota_units_estimate: 1402
videos:
  - url: https://www.youtube.com/watch?v=XXXXXXXXXXX
    title: How to Throw a Teep Kick
    description: ...
    thumbnail_url: https://i.ytimg.com/vi/.../hqdefault.jpg
    channel_name: Muay Thai Guy
    channel_url: https://www.youtube.com/channel/UC...
    channel_avatar_url: https://yt3.ggpht.com/...
    view_count: 412903
    like_count: 11820          # null if the creator hides likes
    tags: [tutorial, educational]
    source_queries:            # the search(es) that surfaced it
      - how to throw a teep kick step by step
    relevance_index: 0         # best search position; 0 = top hit, lower = more relevant
```

### Quota / cost

The YouTube Data API is a **daily quota of 10,000 units** per Google Cloud
project (resets midnight PT) — not a per-request rate limit, and there is **no
pay-per-call pricing**. Costs:

| Call | Units | Used for |
|---|---|---|
| `search.list` | **100** (flat, 1–50 results) | the search itself — the cost driver |
| `videos.list` | 1 (per 50 ids) | view + like counts |
| `channels.list` | 1 (per 50 ids) | creator profile picture |

One brief (10–20 searches) ≈ **1,000–2,000 units** → ~5–10 full runs/day on the
free quota. The script prints its `quota_units_estimate` and writes it into the
output. Because the output is a **cache**, you pay the 100-unit search cost once
per query, not per app open.

**Need more?** There's no buy-more option — you request an increase via Google's
*YouTube API Services Audit and Quota Extension* form. Grants track demonstrated
usage (apps with real traffic routinely get 100k–1M units/day). At MVP scale the
free quota is plenty; the cache is what makes it stretch.

> Dislike counts are intentionally absent — YouTube removed `dislikeCount` from
> the Data API on 2021-12-13, so there is no dislike data to fetch.

## Audit the feed (remove anti-gym videos)

Raw search results include videos that work against the gym — contrarian takes
("why muay thai doesn't work") and `avoid_desc` matches. The **`audit-output`
skill** (`.claude/skills/audit-output/`, invoke with `/audit-output`) curates a
company's `videos_output.yaml` by hand, but **context-lean**: it reasons over a
compact title list, not the whole file.

It's backed by two helper commands so the skill never loads the full output into
context:

```bash
# compact list — one `<video_id>\t<title>\t<channel>` line per video
poetry run python -m scripts.youtube_batch.audit list --app-id combatden

# drop videos by id: survivors rewritten in place, removed ones logged
poetry run python -m scripts.youtube_batch.audit remove --app-id combatden \
    --ids VIDEOID1,VIDEOID2 --reason "negative about muay thai"
```

`remove` rewrites `videos_output.yaml` with the survivors (the API serves the
clean set immediately) and appends each removed video + reason + timestamp to
`videos_output.removed.yaml` (recoverable).

## Class cards (`class_output.yaml`)

`apps/<app_id>/class_output.yaml` holds **exactly four** branded class cards that
replace the mobile app's hardcoded class images. Each card: `name`, a horizontal
`image_url` (class image), a `description`, and the instructor (`instructor_name`,
`instructor_bio`, `instructor_image_url`). It's authored by **Phase 4 of the
`video-brief` skill** and served at `GET /apps/<app_id>/classes`.

> **Known limitation (TODO):** the class/headshot images are hotlinked from the
> internet — links rot, can be hotlink-blocked, and carry licensing risk on a
> customer-facing screen. Durable answer: owned/hosted images (generated via
> CustomizationService, or gym-uploaded). This is the interim brand-match step.

## TODO: automated relevance / sentiment validation (pre-MVP, business-critical)

> Still **pre-MVP** — this is a required step on the path to the MVP, not a
> later nice-to-have. The current demo skips it; the MVP cannot. The
> `audit-output` skill above is the **manual, interim** version — a human (via
> Claude) judges each title. The TODO below is the **automated** replacement.

Right now `avoid_desc` in the brief is **documentation only** — nothing enforces
it. Raw `search.list` results include off-message videos: e.g. a Muay Thai brief
surfaces "why Muay Thai doesn't work" and similar contrarian/negative content.
**This is fine for the demo, but ships garbage to real gyms and would kill the
product in production** — a gym's branded feed cannot recommend videos that
trash the gym's own discipline.

The fix is a validation pass that scores each video (title + description, maybe
channel) against the brief's `videos_desc` / `avoid_desc` and drops the ones
that don't fit, before writing `videos_output.yaml`.

Cost is the design constraint: ~50 results × ~20 searches ≈ **2,000 videos per
brief**, so a naive one-LLM-call-per-video approach gets expensive fast. Options
under consideration (to be spiked separately):

- **Free / near-free local model** — a small locally-hosted model (Gemma,
  Mistral, or similar edge model), even CPU-only. This reasoning is basic enough
  that a cheap model should handle it; latency doesn't matter (offline batch).
- **Batch multiple titles per call** — judge N videos in one prompt instead of
  one call each, cutting call volume by ~N×.
- **Provider batch mode** — this isn't latency-sensitive, so a batch API
  (~50% cheaper) is a good fit if we use a hosted model.

Net: combine batched prompts + batch mode + a cheap/local model and the
per-brief validation cost should round to ~free. Needs its own design pass.

## Tests

```bash
make test
```
