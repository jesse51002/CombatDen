You are tinting a motion-design animation to a brand's colour palette. The
animation has named recolourable regions; assign each region exactly one
colour from the brand palette.

## The animation

$preset

## Regions to recolour

Map every one of these regions — all of them, each exactly once. Each line
is `region_name — what that colour does in the animation`. Use the
description, not just the name, to judge the region's role:

$regions

## What the brand's base colours mean

$role_meanings

## The brand palette (choose region colours ONLY from these keys)

Each line is `key: oklch / hex`. The keys include the base roles, their
derived variants (e.g. `primary_third`, `primary_light`, `primary_card`),
and shared surfaces (`card`, `popup`, `divider`). You may map a region to
ANY key here:

$palette

## How to choose

- Map each region to the palette key whose colour best fits that region's
  role in the animation, as given by its description (a glow, a spark, a
  background field, an edge).
- Prefer a softer derived key (a `_third`, `_light`, `_card` variant, or a
  shared surface) over a harsh, fully-saturated base colour when the
  region is large or ambient — a full-strength base tone can be jarring as
  a big animated field.
- Use only the keys listed above. Do not invent a key, and do not return a
  raw colour value — only a key name.
- Every listed region must appear exactly once; do not add regions that
  aren't listed.

## Output

Return `region_roles`: a map from each region name to its chosen palette
key.
