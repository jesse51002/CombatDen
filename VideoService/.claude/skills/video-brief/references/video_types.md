# VideoType option bank

The fixed genre vocabulary every `videos_config.yaml` search draws from
(`schema/video_type.py`). Each search's `tags` is a **non-empty list** of these — a
single query often spans several. A good 5-search set reaches broadly across the
spectrum (5+ distinct genres), weighted toward the genres that matter most for the company.

Below: what each genre means, and example search-prompt *shapes* (replace the niche with
the company's). These are shapes to adapt, not phrases to copy.

---

## entertainment
Broad watch-for-fun content in the niche — the stuff people put on to enjoy, not to study.
- `best <niche> moments of 2024`
- `most satisfying <niche> videos`

## educational
Teaching concepts, explainers, courses — the "understand it" content.
- `<niche> for beginners explained`
- `the science behind <niche concept>`

## tutorial
Step-by-step how-to / technique — the "do it yourself" content.
- `how to <specific skill> step by step`
- `<technique> tutorial for beginners`

## informative
Facts, breakdowns, analysis, deep dives — denser than educational, often opinionated.
- `<niche topic> breakdown / analysis`
- `does <common claim> actually work`

## news
Current events, announcements, releases, updates in the niche.
- `<niche / brand> news this week`
- `<upcoming event> latest updates`

## interview
Podcasts, Q&A, long-form conversations with figures in the space.
- `<notable figure> interview on <topic>`
- `<niche> podcast with <expert>`

## vlog
Day-in-the-life, personal journeys, first-person experience.
- `day in the life of a <role>`
- `my <niche> journey / progress vlog`

## behind_the_scenes
Process, making-of, how the work / business actually runs.
- `behind the scenes at a <business type>`
- `how <thing> is really made`

## professional
**PROS practising the craft at the top level** — elite athletes / competitors performing,
pro competition footage, championship play. NOT corporate or high-production video.
- `<top pro> vs <top pro> full <match/fight/performance>`
- `<elite event / league> highlights`

## clips
Short highlights, moments, compilations — bite-size, high-shareability.
- `<niche> highlights compilation`
- `best <moments> short clips`

## fun
Memes, lighthearted, funny moments — pure levity.
- `funny <niche> fails / moments`
- `<niche> bloopers compilation`

---

## Coverage cue

When drafting, sanity-check the set touches at least these clusters:
- **teach** — educational, tutorial
- **enjoy** — entertainment, clips, fun
- **trust** — informative, news
- **human** — vlog, interview, behind_the_scenes
- **peak** — professional

If a whole cluster is missing, the set is too narrow — add a search for it (weighted by
how much that cluster matters to the company).
