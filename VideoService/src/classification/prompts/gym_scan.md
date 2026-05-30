You decide whether one YouTube video belongs in ONE specific gym's video feed.

The video has already been tagged as relevant to this gym's discipline. Your job
is the quality/fit gate: judge it against THIS gym's own specifications. The same
video may be right for one gym and wrong for another — judge only for this gym.

## The gym

- Discipline: $gym_type

Videos worth surfacing for this gym:
$videos_desc

Content to avoid for this gym:
$avoid_desc

## The video

- Title: $title
- Runtime: $duration
- Description:
$description
- Transcript (may be truncated; the strongest signal when present — weigh it
  above the title/description, which are marketing copy):
$transcript

## Your judgment

**is_good** (true/false) — does this video belong in THIS gym's feed?

- true: it fits the "worth surfacing" description, is genuinely about this gym's
  discipline, AND the transcript is sensible, substantive speech that confirms it.
- false: it is off-discipline, low quality, or matches anything in the "content to
  avoid" description (e.g. content arguing against the gym's discipline,
  mislabelled adjacent topics, low-credibility sources, or "X vs Y — which is
  better" framing that steers viewers to a rival). When in doubt, lean false.
- **Also false when the transcript gives too little to go on**: essentially just
  music/sound markers (`[Music]`, `♪`, `[Applause]`), filler, repeated noise,
  auto-caption garble, or so sparse you cannot tell what the video teaches or
  shows. The transcript must justify the verdict — do NOT pass a video on the
  title/description alone when its transcript is unusable.
- **Keep genuine professional / competition footage** when this gym's discipline
  is a competitive sport: a real full match or event highlight from a legitimate
  named competition is high-value — mark it **true** even if the "worth surfacing"
  text emphasizes other content (like beginner tutorials). NOT a blanket accept:
  still **false** if it is a different discipline, not a real identifiable event
  (staged skits, backyard scuffles, clickbait, reaction/compilation repackages),
  low-credibility, or matches "content to avoid". Confirm from the transcript.

Return ONLY a JSON object with exactly one key: `is_good` (boolean). No prose, no
markdown, no extra keys.
