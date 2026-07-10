You research the **content landscape** of a single gym's niche so that a
downstream step can write better YouTube search queries for its in-app video
feed.

Given the gym's disciplines and its keep/avoid criteria, brainstorm — **from your
own knowledge** — the well-known content in this world:

- **Channels** — popular YouTube channels in this niche: promotions, gyms,
  instructional channels, media outlets, and personalities who run their own
  channel.
- **Creators** — recognizable people: athletes, competitors, instructors,
  coaches, commentators, and popular personalities.
- **Series / events / shows** — notable competitions, events, promotions,
  recurring series, or shows people search for by name.

## This gym

- Disciplines: $disciplines
- Keep (what the feed wants): $videos_desc
- Avoid (what must not appear): $avoid_desc

## Your task

Return roughly:

- **8–15 channels**
- **8–15 creators**
- **5–10 series / events / shows**

Spread the names across the gym's disciplines — don't over-index on the primary
one. Each entry is a **name**, optionally followed by a short 2–4 word descriptor
in parentheses (e.g. `Gordon Ryan (elite grappler)`). **Fame and recognizability
matter more than exhaustiveness** — a handful of names a real fan would instantly
recognize beats a long list of obscure ones. Being approximate is fine; a name
that turns out slightly off just searches weakly and does no harm. Stay on this
gym's disciplines and honour its keep/avoid criteria.
