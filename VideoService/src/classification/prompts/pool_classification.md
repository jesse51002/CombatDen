You tag one YouTube video for a shared, gym-agnostic video pool.

You are given only the video's own content (title, description, runtime, and —
when available — the transcript). You do NOT decide whether any gym should show
it; that is a separate per-gym step. You make two purely descriptive judgments
about what the video IS.

## The video

- Title: $title
- Runtime: $duration
- Description:
$description
- Transcript (may be truncated; the strongest signal when present — weigh it
  above the title/description, which are marketing copy):
$transcript

## Your two judgments

1. **tag** — the SINGLE content genre the video actually is, judged from its
   title, description, runtime, and transcript. Pick exactly one best fit from
   this fixed vocabulary:

   - `educational` — teaching a technique or concept; "understand it / do it".
   - `analysis` — post-analysis or breakdown of content, usually to educate
     (deeper / more opinionated than a plain how-to).
   - `entertainment` — broad watch-for-fun content; put on to enjoy, not study.
   - `news` — current events, announcements, updates.
   - `interview` — podcasts, Q&A, long-form conversations with figures.
   - `vlog` — day-in-the-life, personal journeys, first-person experience.
   - `professional` — pros/elite athletes & competitors performing; specifically
     full matches or highlights from a specific event. NOT corporate video.
   - `clips` — a single short moment/highlight, or a compilation of short
     moments (runtime is a strong signal — very short videos are often `clips`).
   - `memes` — memes, lighthearted, funny moments; pure levity.

2. **gym_type** — the LIST of fitness **disciplines** this video is genuinely
   relevant to, from the fixed vocabulary below. A video usually belongs to ONE
   discipline; assign several only when the content truly spans them (e.g. a
   kettlebell-and-rowing conditioning piece → `[kettlebell, rowing]`). Be
   accurate, not generous: a member of a discipline should never be shown a video
   that isn't really about their practice. Return at least one. If the video is
   not about any of these disciplines at all, return the single closest one — a
   later per-gym step will reject off-topic videos.

   Allowed disciplines (use these exact strings):
$gym_type_vocab

Return ONLY a JSON object with exactly these keys: `tag` (one genre string above)
and `gym_type` (a non-empty list of discipline strings above). No prose, no
markdown, no extra keys.
