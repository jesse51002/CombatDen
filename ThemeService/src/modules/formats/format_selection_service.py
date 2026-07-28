"""FormatSelectionService — the ONE structured LLM call that picks a value
for every format slot the app declares.

The LLM sees the design name + the brand brief, then every requested slot
with its description and its own closed list of values (each value with
its description), and returns one pick + one reason per slot. The
known-value contract rides the existing ``complete_structured`` retry loop
via the per-request model's after-validator (see
``build_format_response_model``); a missing slot rides it too, because
every field on that closed model is required.

**One call for every slot, not one call per slot.** The picks are not
independent: they are the same product's arrangement seen by the same
user in one session, so a per-slot call would optimise each surface in
isolation and produce a product that disagrees with itself.
One call also sends the brand brief once instead of once per slot, which
is where most of the token cost lives. The batched shape is already the
package's norm for exactly this reason — the colour module resolves the
whole palette in one call, the text module the whole copy set, the icon
module the whole match set. The usual objection (one bad field re-asks
everything) is answered by the icon module's precedent: the whole-batch
retry loop re-asks with an error naming ONLY the offending slots and
their permitted values, and the prompt tells the model to keep the
answers it already gave for the rest.

A partial regen narrows the call rather than splitting it: ``only``
scopes both the prompt and the closed schema to the dirty slots, and the
already-decided slots are shown as fixed context so the re-roll stays
coherent with them — the same ``only`` / ``fixed`` shape
``TextGenerationService`` uses.

App-agnostic by construction: the slots and every value are read off
``run_ctx.app.formats`` at call time and never appear in Python. An app
that declares none never gets this node built (the registry skips it), so
this service is only ever reached with a non-empty inventory.
"""

from __future__ import annotations

from pathlib import Path
from string import Template

from schema import FormatOutput, FormatSet, FormatSlot
from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.modules.formats.format_models import build_format_response_model
from src.shared.interfaces.llm_client import LLMClient

FORMAT_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "format_selection.md"
)

# Model for the format call. A per-call constant, not config: the model is
# a property of this call. Override via ``resolve(model=...)`` in dev;
# production uses this default.
#
# SONNET, NOT HAIKU, AND THE SHAPE OF THE CALL IS WHY. This looks
# classify-shaped — a closed single-label pick per slot, schema-constrained
# and vocabulary-validated — and it was run on Haiku for exactly that
# reason. The output shape is not the difficulty. What is being asked for
# is TASTE: which arrangement a brand should live in, judged from prose
# about that brand, thirteen times over, coherently. Haiku answered it the
# way a small model answers an aesthetic question — it found a safe value
# per slot and repeated it, returning the same app-shell arrangement for 74
# of 76 differently-branded gyms.
#
# So this belongs with the COLOUR call (``COLOR_MODEL``), the package's
# other judgement call, rather than with the classify-shaped ones
# (classification, icon-set selection, text generation) it superficially
# resembles. The vocabulary describes each arrangement and stops; deciding
# which one suits a brand is the model's job, and it needs a model that can
# do it.
FORMAT_MODEL = "anthropic/claude-sonnet-4-6"


class FormatSelectionService:
    """Builds the format prompt and runs the one structured call that
    picks a value for every requested slot from its own vocabulary."""

    def __init__(self, llm: LLMClient) -> None:
        self._llm = llm

    async def resolve(
        self,
        run_ctx: RunContext,
        *,
        model: str = FORMAT_MODEL,
        only: set[str] | None = None,
        fixed: dict[str, FormatOutput] | None = None,
    ) -> FormatSet:
        """Run the one format call; return the chosen value per slot.

        ``only`` scopes the call to a subset of slot ids (a partial
        regen); ``fixed`` supplies the already-decided values shown as
        context so the re-roll stays coherent with them. With both unset
        every declared slot is resolved — the full-run behaviour. The
        run's steering (``run_ctx.overwrite_specs``) is folded into the
        prompt and stamped onto each returned ``FormatOutput``.

        Raises:
            ProviderError: the app declares no format slots, so there is
                nothing to pick and no vocabulary to pick from.
                Structurally unreachable via the registry (which skips the
                node entirely in that case); this is defense-in-depth for
                a direct caller.
        """
        if not run_ctx.app.formats:
            raise ProviderError(
                "app declares no formats — nothing to select"
            )
        target = [
            slot
            for slot in run_ctx.app.formats
            if only is None or slot.id in only
        ]
        if not target:
            # No slots requested — nothing to do. (The node is the primary
            # skip path; this is defense-in-depth.)
            return FormatSet(formats={})
        target_ids = {slot.id for slot in target}
        # Fixed context is the prior pick for slots NOT being re-rolled.
        fixed_context = {
            sid: out.value
            for sid, out in (fixed or {}).items()
            if sid not in target_ids
        }

        response_model = build_format_response_model(target)
        messages = [
            {
                "role": "user",
                "content": self._build_prompt(
                    run_ctx, target, fixed_context=fixed_context
                ),
            }
        ]
        resolved = await self._llm.complete_structured(
            messages, schema=response_model, model=model
        )
        return FormatSet(
            formats={
                slot.id: FormatOutput(
                    value=getattr(resolved, slot.id).value,
                    reason=getattr(resolved, slot.id).reason,
                    overwrite_specs=run_ctx.overwrite_specs,
                )
                for slot in target
            }
        )

    @staticmethod
    def _build_prompt(
        run_ctx: RunContext,
        slots: list[FormatSlot],
        *,
        fixed_context: dict[str, str],
    ) -> str:
        """Rule + brand brief + already-decided picks + the slot inventory
        (each slot with its own described vocabulary), substituted into
        the one ``.md`` template (``safe_substitute`` tolerates a stray
        ``$``). The run's steering note is appended under the slots, so
        ``regen --slot <format slot> --spec "…"`` can correct a pick in
        words."""
        template = FORMAT_PROMPT_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        note = run_ctx.overwrite_specs.prompt_note()
        blocks = []
        for slot in slots:
            values = "\n".join(
                f"    - {entry.value}: {entry.description}"
                for entry in slot.values
            )
            blocks.append(f"- {slot.id}: {slot.description}\n{values}")
        fixed_block = (
            "\n".join(
                f"- {sid}: {value}" for sid, value in fixed_context.items()
            )
            or "(none — every slot below is open)"
        )
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            colors=run_ctx.cust.colors_direction.description,
            fixed_context=fixed_block,
            slots="\n\n".join(blocks),
            note=f"\n{note}" if note else "",
        )
