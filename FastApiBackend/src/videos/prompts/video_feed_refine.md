You are refining a gym's video-feed specification based on signals from the owner's
manual curation actions.

The spec controls what videos appear in the gym's in-app feed: `videos_desc` describes
the content that should be INCLUDED; `avoid_desc` describes what must be EXCLUDED.

## The gym's CURRENT spec

**Disciplines:** $current_disciplines

**Keep criteria (videos_desc):**
$current_videos_desc

**Avoid criteria (avoid_desc):**
$current_avoid_desc

## Manual curation signals

These are the owner's own hands-on decisions about specific videos since the last
time the spec was updated from feed curation. Each entry includes:
- The video's **title** and **channel**
- The owner's **action** (manually rejected or manually kept / re-added)
- The owner's **stated reason** (if they gave one)
- A **description snippet** from the video's metadata (if available)
- A **transcript snippet** from the video's captions (if available)

Use all of this context — especially the description and transcript — to understand
*why* a video triggered the signal and *what specifically* the current spec got wrong.

$signals

### How to read the signals

- **MANUALLY REJECTED:** The owner rejected a video the automatic scan had accepted.
  The current `videos_desc` wrongly INCLUDED it. The description / transcript / owner
  reason tell you what kind of content this is and why it does not fit.
  → Tighten `avoid_desc` to exclude that kind of content. Tighten `videos_desc` only
    if it clearly mis-invited that kind of video. Do NOT relax inclusion criteria.

- **MANUALLY KEPT / RE-ADDED:** The owner kept or re-added a video the automatic scan
  had rejected. The current `avoid_desc` or `videos_desc` wrongly EXCLUDED it. The
  description / transcript / owner reason tell you what kind of content this is and
  why it does belong.
  → Widen `videos_desc` to welcome that kind of content. If `avoid_desc` incorrectly
    barred it, narrow the avoid language to stop barring it. Do NOT tighten exclusions.

## Rules you must follow

- **Use the description and transcript.** They are the richest signal you have about
  what a video actually contains. Rely on them — not just the title — when deciding
  how to update the criteria.

- **NEVER reject content by format.** Do not add rules like "no short clips",
  "no vlogs", "no highlights", "no reaction videos", or "no compilations". The format
  is never the problem — only topic / quality / discipline mismatch matters.

- **Preserve what is working.** Only change the parts the curation signals call into
  question. Leave criteria that are not implicated by any signal alone.

- **Honor the owner's stated reason.** When an owner gave a reason, it is the most
  direct signal you have — weigh it heavily over your own interpretation of the title
  or description.

## Your task

Produce improved criteria (disciplines, videos_desc, avoid_desc, short_videos_desc,
short_avoid_desc) that better capture the owner's demonstrated taste based on the
signals above. Condense each long description into a ~2-sentence short version.
Do NOT include search queries — those are generated separately.
