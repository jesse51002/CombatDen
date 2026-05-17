You are validating an image cutout.

The attached image should contain ONLY the subject on a fully transparent
background: every pixel that is not the subject must be transparent, and the
subject itself must be complete and undamaged — no missing edges, no holes
punched through it, no parts erased.

Decide:

- `ok` is true only if the background is fully removed AND the subject is
  fully intact.
- `ok` is false if any background remains, the subject is partially erased,
  or the cutout is otherwise unusable.

Give a one-sentence reason for the verdict.
