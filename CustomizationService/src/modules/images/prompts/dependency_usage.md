--- Related assets (visual continuity) ---
The assets below were already generated for THIS SAME app. This image
should look like it came from the same hand — match their medium,
materials, finish and palette discipline so the set is coherent. Do NOT
copy their subject, composition or wording; this is its own distinct
subject.

For EACH related asset you ALSO decide how it should inform this image
and return that decision in the `dependency_usage` list — exactly one
entry per asset, `dependency` set to the asset's id EXACTLY as listed,
`usage` either `reference` or `direct`:

- Pick `reference` when this image only needs to *match the style,
  material, finish, palette, or family* of that asset — it is a
  sibling/companion asset that should look like it came from the same
  hand, but is its own distinct subject. The asset's description below is
  enough to steer the prompt; the asset image itself does not need to
  appear. Fold its look into the `prompt` text.

- Pick `direct` when this image must actually *contain* that asset, or
  something so close to it that re-generating from words alone would not
  be faithful enough — e.g. the same object shown again, a tighter/looser
  crop of it, the same emblem placed onto something, or a variation that
  must preserve that exact specific artwork. The asset image itself is
  fed to the generator, so do NOT describe that asset in `prompt`;
  instead write `prompt` as the instruction for how the result is built
  from / around it.

When unsure, prefer `reference`: it is the cheaper, lower-risk default
and covers the common "keep these assets visually consistent" case.
Reserve `direct` for a genuine "this specific image must be in/under the
result".

Related assets (use these ids exactly in `dependency_usage`):
$dependencies
