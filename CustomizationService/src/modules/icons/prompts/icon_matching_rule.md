You are matching UI icon concepts to a curated icon set for a real,
shipped consumer app. The brand and the chosen set are described below.
For EACH icon slot you are given an id and a short description of the
concept it represents ("checkmark", "navigation home tab", "send
message"). Your job: pick the icon from the chosen set that best
represents each slot — or honestly say nothing fits.

This is one batched decision. You see every slot and the set's whole icon
vocabulary at once.

THE HONESTY RULE — read this twice. For each slot, return the set icon
short-name that genuinely represents the concept. If NO icon in the set
honestly represents it, return `null`. A wrong-but-close icon is worse
than no icon: a `null` routes the slot to generation, which produces a
purpose-drawn icon in the set's style. Do NOT stretch a loosely-related
icon to avoid a `null`. "A heart for a favourites tab" — yes. "A heart
for a medical-records tab" — no, that's a stretch; return `null`.

- Match on MEANING, not on word overlap. The concept's description is
  what matters, not whether a label string happens to match.
- Only ever return an icon short-name that appears in the set's icon list
  below, spelled exactly. Anything else fails validation and you'll be
  re-asked.
- When two set icons both fit, pick the more conventional / less
  surprising one for that concept in app UI.

OUTPUT. For EACH slot return an object with two fields:

- `icon`: the chosen set icon's short-name (exactly as listed), or `null`
  if nothing in the set honestly fits.
- `match_reason`: one short clause — why this icon, or why nothing fit.
  Record-keeping, not marketing.

--- Brand brief ---
Brand name: $name
In short: $short
In depth: $long

--- Chosen icon set ---
Name: $set_name
Vibe: $set_vibe
Icons in this set: $icons

--- Icon slots to match ---
$slots
