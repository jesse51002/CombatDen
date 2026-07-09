You enrich one YouTube video for a shared, gym-agnostic video pool.

You are given the video's own content (title, channel, description, runtime, and
— when available — the transcript) AND its thumbnail image (attached). You do NOT
decide whether any gym should show it; that is a separate per-gym step. You make
four descriptive judgments about what the video IS.

## The video

- Title: $title
- Channel: $channel
- Runtime: $duration
- Description:
$description
- Transcript (may be truncated; the strongest textual signal when present — weigh
  it above the title/description, which are marketing copy):
$transcript

The thumbnail image is attached. USE IT: it carries signal the text misses —
attire (e.g. gi vs no-gi, uniform vs streetwear), setting (competition mat, home
gym, studio, outdoors), and production style (professional broadcast, phone clip,
graphic-heavy).

## Your four judgments

1. **tag** — the SINGLE content genre the video actually is. Pick exactly one best
   fit from this fixed vocabulary:

   - `educational` — teaching a technique or concept; "understand it / do it".
   - `analysis` — post-analysis or breakdown of content, usually to educate.
   - `entertainment` — broad watch-for-fun content; put on to enjoy, not study.
   - `news` — current events, announcements, updates.
   - `interview` — podcasts, Q&A, long-form conversations with figures.
   - `vlog` — day-in-the-life, personal journeys, first-person experience.
   - `professional` — pros/elite athletes competing; a full match or highlights
     from a specific real event. NOT corporate video.
   - `clips` — a single short moment/highlight, or a compilation of short moments.
   - `memes` — memes, lighthearted, funny moments; pure levity.

2. **disciplines** — the LIST of fitness disciplines this video is genuinely
   relevant to, from the fixed vocabulary below. Usually ONE; assign several only
   when the content truly spans them (e.g. a kettlebell-and-rowing conditioning
   piece → `[kettlebell, rowing]`). Be accurate, not generous. Return at least
   one; if it is about none of these, return the single closest one (a later
   per-gym step rejects off-topic videos).

   Allowed disciplines (use these exact strings):
$gym_type_vocab

3. **summary** — a detailed, self-contained paragraph (aim for ~4–8 sentences)
   describing what the video IS. This summary does double duty: it is embedded for
   recommendation ranking AND it is the ONLY thing a later per-gym keep/drop step
   sees — that step never gets the thumbnail or the transcript, just this text. So
   anything you omit is invisible to it. Be thorough and concrete, covering:
   - the actual subject and what the video does (teaches technique X, breaks down a
     match, full bout between named competitors, day-in-the-life, etc.);
   - what the THUMBNAIL shows — attire (gi vs no-gi, uniform vs streetwear), the
     setting (competition mat, home gym, studio, outdoors), and the production
     style (professional broadcast, phone clip, graphic-heavy clickbait);
   - who is in it (named athletes, coaches, or identifiable events/promotions);
   - the format and skill level (tutorial vs highlight vs full match; beginner vs
     advanced) and any quality/credibility signals.
   Prefer specific nouns over vague praise. Do NOT make it a one-liner — a terse
   summary starves the keep/drop step of the signal it needs.

4. **facets** — a small free-shape object of structured attributes you can read
   off confidently, e.g. `{"gi": false, "setting": "competition",
   "skill_level": "beginner"}`. Values may be strings, booleans, or integers.
   Include only attributes you are confident about; an empty object is fine.

Return ONLY a JSON object with exactly these keys: `tag` (one genre string above),
`disciplines` (a non-empty list of discipline strings above), `summary` (string),
and `facets` (object). No prose, no markdown, no extra keys.
