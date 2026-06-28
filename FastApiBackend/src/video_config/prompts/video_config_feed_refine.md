You are refining a gym's video-feed specification based on signals from the owner's
manual curation actions.

The spec controls what videos appear in the gym's in-app feed: `videos_desc` describes
the content that should be INCLUDED; `avoid_desc` describes what must be EXCLUDED;
`queries` are the YouTube search phrases that fill the candidate pool.

## The gym's CURRENT spec

**Disciplines:** $current_disciplines

**Keep criteria (videos_desc):**
$current_videos_desc

**Avoid criteria (avoid_desc):**
$current_avoid_desc

**Current search queries:**
$current_queries

## Manual curation signals

These are the owner's own hands-on decisions about specific videos since the last
time the spec was updated from feed curation. Each signal tells you something the
current spec got wrong:

$signals

### How to read the signals

- **REJECTED (scan_status = rejected, rejection_type = manual):** The owner manually
  rejected a video the automatic scan had accepted as a match. The current `videos_desc`
  wrongly INCLUDED it. The owner's optional reason tells you why it was wrong.
  → Tighten `avoid_desc` to exclude that kind of content. Tighten `videos_desc` only
    if it clearly mis-invited that kind of video. Do NOT relax inclusion criteria.

- **KEPT / RE-ACCEPTED (scan_status = accepted with a prior rejection, or newly added
  by the owner):** The owner kept or re-added a video the automatic scan had rejected.
  The current `avoid_desc` or `videos_desc` wrongly EXCLUDED it.
  → Widen `videos_desc` to welcome that kind of content. If `avoid_desc` incorrectly
    barred it, narrow the avoid language to stop barring it. Do NOT tighten exclusions.

## Rules you must follow

- **NEVER reject content by format.** Do not add rules like "no short clips",
  "no vlogs", "no highlights", "no reaction videos", or "no compilations". The format
  is never the problem — only topic / quality / discipline mismatch matters.

- **Spread queries across the nine video genres:** `educational`, `analysis`,
  `entertainment`, `news`, `interview`, `vlog`, `professional`, `clips`, `memes`.
  Aim for roughly half teach/how-to and half enjoy + human + peak. Never let the
  all-educational set dominate. Fun, entertaining, clip, highlight, vlog, and
  interview content is explicitly wanted.

- **Queries must be concrete search phrases** a real person would type into YouTube —
  specific to this gym's world, not topic labels or genre names.

- **Keep the full spec.** Produce ALL fields of the improved config — disciplines,
  videos_desc, avoid_desc, short_videos_desc, short_avoid_desc, and queries. Do not
  drop or blank any field.

- **Preserve what is working.** Only change the parts the curation signals call into
  question. Leave criteria and queries that are not implicated by any signal alone.

## Your task

Produce a complete improved spec (all fields) that better captures the owner's
demonstrated taste, based on the signals above.
