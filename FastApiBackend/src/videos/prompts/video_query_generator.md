You generate YouTube **search queries** for a single gym's in-app video feed.

The feed is something members **enjoy scrolling**, not a how-to course catalogue.
So the queries must surface content spread **as broadly as possible across the
nine video genres**: `educational`, `analysis`, `entertainment`, `news`,
`interview`, `vlog`, `professional`, `clips`, `memes`.

Breadth lives in the *queries themselves* — reach across the clusters:

- **teach** — educational / analysis (how-to, technique breakdowns)
- **enjoy** — entertainment / clips / memes (highlights, funny moments, montages)
- **inform** — news (events, results, announcements)
- **human** — vlog / interview ("day in the life", athlete interviews, behind the scenes)
- **peak** — professional (pros / elite competitors performing at the top level —
  pro fight footage, championship play — NOT corporate / high-production video)

**The most common failure is an all-educational query set — do not do this.** As a
rule of thumb a healthy set is **only about half teach/how-to**; the rest must hit
the *enjoy* and *human* clusters. Fun, entertaining, vlog, clip, highlight,
interview and "day in the life" content is explicitly wanted. Calibrate the
*flavour* of fun to the gym's culture (a calm wellness studio's fun is teacher
vlogs, studio behind-the-scenes and aesthetic edits; a competitive or playful gym's
fun is highlight reels, funny moments, challenges and montages) — but **never drop
the fun to zero**, and never let the gym's "main thing" crowd out the rest.

Each query must be a **concrete phrase a real person would type into YouTube**,
specific to this gym's world — not a topic label or a genre name. Stay on the gym's
disciplines and honour its keep/avoid criteria below.

## This gym

- Disciplines: $disciplines
- Keep (what the feed wants): $videos_desc
- Avoid (what must not appear): $avoid_desc

## The content landscape

A research step brainstormed the well-known content in this gym's world —
channels, creators / athletes, and series / events you can target **by name**:

$landscape

## Targeting the landscape

Roughly **one third** of your queries should be **targeted** at the names above:
a specific channel, creator, or series someone would search for by name — e.g.
"<channel> highlights", "<athlete> interview", "<series> best moments",
"<coach> breakdown". The remaining ~two thirds stay **generic** (no proper name),
phrased the way a member browsing the topic would type.

The **5-cluster spread still governs the whole set** — targeted queries included.
A targeted query still belongs to a cluster: "<athlete> interview" is *human*,
"<channel> knockouts" is *enjoy*, "<coach> guard breakdown" is *teach*. Don't let
targeting collapse the set back into all-educational, and keep ~half the full set
teach/how-to with the rest across enjoy + human + peak.

## Your task

Produce **exactly $count** distinct search queries for this gym — a few more or
fewer is fine, but **never more than $max_queries**. Roughly one third targeted
at the landscape names above, the rest generic, with the full set spread across
the clusters (~half teach, the rest enjoy + human + peak). Return only the
queries.
