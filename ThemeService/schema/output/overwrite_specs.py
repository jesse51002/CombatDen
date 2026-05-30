"""OverwriteSpecs — the agent-authored steering for (re)generating a slot.

This is the single object a reopen-time regeneration is steered by. It rides on
the ``RunContext`` (``run_ctx.overwrite_specs``) — every layer (executor →
registry → node → service) already carries the context and reads the steering
off it, so nothing hand-threads it as a parameter. It is also recorded on each
per-item output (``NodeOutput.overwrite_specs``) so a saved slot says exactly
what produced it.

**It is the agent's job to populate this with whatever helps the
regeneration.** Carrying everything on one extensible object (rather than
wiring a new parameter for each need) is the point: a new knob for one module
is a new field here, not a new signature across the call chain. Today:

- ``specs`` — the free-text instruction. This is where the agent says
  everything in words: what they want AND what already didn't work / to avoid.
  It is one string, not a structured set of fields.
- ``image_to_image`` — the image module only: present ⇒ edit the slot's current
  image instead of generating fresh; absent ⇒ create-new.

Future modules add their own optional fields here. ``extra="ignore"`` matches
the other output-read models; a bare string is coerced to
``OverwriteSpecs(specs=...)`` at the validation boundary (see ``NodeOutput``)
so callers and older artifacts can still use the plain string form.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class ImageToImage(BaseModel):
    """Image-to-image edit settings (the image module only).

    Its **presence** on an ``OverwriteSpecs`` selects editing the slot's
    *current* image over generating a fresh one; absent ⇒ create-new. The edit
    instruction is the parent ``OverwriteSpecs.specs``. Phase 3 adds the
    provider knobs the edit needs (e.g. how strongly to preserve the original);
    the field exists now so enabling edits never needs a new wired parameter.
    """

    model_config = ConfigDict(extra="ignore")


class OverwriteSpecs(BaseModel):
    """Agent-authored steering for one regen: the free-text ``specs`` plus any
    module-specific knobs."""

    model_config = ConfigDict(extra="ignore")

    specs: str = ""
    image_to_image: ImageToImage | None = None

    def prompt_note(self) -> str:
        """The steering rendered for a module prompt, or ``""`` when there's
        nothing to add.

        A data block (like a slot inventory), not the rule itself: every
        module appends it under its slots so the model honors the ask (which
        the agent phrases freely — including anything to avoid). The rules stay
        in each ``.md``.
        """
        if not self.specs:
            return ""
        return f"User override (honor this): {self.specs}"
