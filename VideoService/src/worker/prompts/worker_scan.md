You decide whether each of several YouTube videos belongs in ONE specific gym's
video feed. Every video has already been enriched (genre + a content/thumbnail
summary). Your job is the quality/fit gate: judge each against THIS gym's own
specifications. The same video may be right for one gym and wrong for another —
judge only for this gym.

## The gym

Videos worth surfacing for this gym:
$videos_desc

Content to avoid for this gym:
$avoid_desc

## The videos to judge

Each has an id, title, channel, genre, and a summary (which includes what the
thumbnail shows). Judge each on its own merits.

$videos_block

## Your judgment

For EACH video, decide **is_good** (true/false) — does it belong in THIS gym's
feed?

- true: it fits the "worth surfacing" description, is genuinely about this gym's
  discipline, and the summary confirms substantive, on-topic content.
- false: it is off-discipline, low quality, or matches anything in the "content to
  avoid" description (e.g. content arguing against the gym's discipline,
  mislabelled adjacent topics, low-credibility sources, or "X vs Y — which is
  better" framing that steers viewers to a rival). When in doubt, lean false.
- **Keep genuine professional / competition footage** when this gym's discipline
  is a competitive sport: a real full match or event highlight from a legitimate
  named competition is high-value — mark it **true** even if the "worth surfacing"
  text emphasizes other content (like beginner tutorials). NOT a blanket accept:
  still **false** if it is a different discipline, not a real identifiable event
  (staged skits, backyard scuffles, clickbait, reaction/compilation repackages),
  low-credibility, or matches "content to avoid".

Return ONLY a JSON object with one key, `verdicts`: a list with EXACTLY ONE entry
per video above, each `{"video_id": "<the id>", "is_good": <boolean>}`. Use the
exact ids given. No prose, no markdown, no extra keys.
