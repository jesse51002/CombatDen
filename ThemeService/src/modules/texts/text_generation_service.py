"""TextGenerationService — owns the batched LLM call(s) that rewrite
every text slot the app declares, plus the per-slot length-bounds
retry loop.

The LLM is asked for one rewritten string per slot, in one structured
call. Each returned string is checked programmatically against its
slot's ``min_words`` / ``max_words`` / ``min_chars`` / ``max_chars``;
violators are re-asked in the next attempt with the prior attempt and
the specific violation message visible to the model. After
``MAX_RETRIES`` attempts, any slot still violating its bounds is
omitted from the returned mapping — the consuming MobileApp falls back
to its bundled default copy in that case (no truncation, no synthetic
fallback string).

This per-slot retry is intentionally NOT the existing whole-batch
``complete_structured`` retry loop: that one re-asks every slot every
attempt and caps at ``settings.llm_max_retries``. The product
requirement here is to re-ask only the violating slots and to cap at a
text-specific budget (``MAX_RETRIES``).

The service returns a fully resolved ``TextSet`` — a slot is in
``texts`` only if its final value satisfied the bounds. An empty
``TextSet`` is a valid (and honest) result: every slot failed, or the
app declared no text slots.
"""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template

from schema import TextOutput, TextSet, TextSlot
from src.core.run_context import RunContext
from src.modules.texts.text_models import (
    LLMTextResponse,
    build_text_response_model,
)
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

TEXT_PROMPT_PATH = Path(__file__).parent / "prompts" / "text_generation.md"

# Model for the text-rewrite call. A per-call constant, not config: the
# model is a property of this call. Override via ``resolve(model=...)``
# in dev; production uses this default. Haiku is plenty — the slot
# descriptions + the brand brief + the programmatic length check do
# the constraining; copywriting volume is small.
TEXT_MODEL = "anthropic/claude-haiku-4-5"

# Maximum number of LLM round-trips the service will spend chasing
# length-bounds compliance. Each attempt re-asks ONLY the slots that
# violated their bounds on the previous attempt (the first attempt is
# every slot). After this many attempts, any still-violating slot is
# dropped from the returned mapping.
MAX_RETRIES = 3


class TextGenerationService:
    """Builds the LLM prompt, runs the structured call, and enforces
    per-slot length bounds via a per-slot retry loop."""

    def __init__(self, llm: LLMClient) -> None:
        self._llm = llm

    async def resolve(
        self,
        run_ctx: RunContext,
        *,
        model: str = TEXT_MODEL,
        only: set[str] | None = None,
        fixed: dict[str, TextOutput] | None = None,
    ) -> TextSet:
        """Resolve the requested text slots.

        Walks up to ``MAX_RETRIES`` rounds: each round asks the LLM for
        every slot still pending, then keeps the ones whose returned
        value sits inside its bounds. The leftover (violating) slots
        carry into the next round with the rejected attempt + the
        violation message folded into the prompt.

        ``only`` scopes the call to a subset of slot ids (a partial regen);
        ``fixed`` supplies the already-written copy shown as fixed context so
        the rewrites stay consistent in voice. The run's steering
        (``run_ctx.overwrite_specs``) is folded into the prompt and stamped onto
        each returned ``TextOutput``. With ``only``/``fixed`` unset every
        declared slot is resolved — the full-run behavior.

        Returns a ``TextSet`` that may be partial: a slot is present
        only if a satisfying value was found within the retry budget.
        """
        target = (
            [s for s in run_ctx.app.texts if s.id in only]
            if only is not None
            else list(run_ctx.app.texts)
        )
        if not target:
            # No slots requested — nothing to do. (The registry / node is
            # the primary skip path; this is defense-in-depth.)
            return TextSet(texts={})
        target_ids = {s.id for s in target}
        # Fixed context is the prior copy for slots NOT being rewritten.
        fixed_context = {
            sid: out.value
            for sid, out in (fixed or {}).items()
            if sid not in target_ids
        }

        results: dict[str, str] = {}
        pending: list[TextSlot] = target
        prior_attempts: dict[str, str] = {}
        prior_violations: dict[str, list[str]] = {}

        for attempt in range(MAX_RETRIES):
            response = await self._call_llm(
                run_ctx,
                pending,
                prior_attempts=prior_attempts,
                prior_violations=prior_violations,
                model=model,
                fixed_context=fixed_context,
            )
            still_violating: list[TextSlot] = []
            prior_attempts = {}
            prior_violations = {}
            for slot in pending:
                value: str = getattr(response, slot.id).value.strip()
                problems = self._check_bounds(value, slot)
                if problems:
                    still_violating.append(slot)
                    prior_attempts[slot.id] = value
                    prior_violations[slot.id] = problems
                    logger.debug(
                        "text slot %r violated bounds on attempt %d: %s",
                        slot.id,
                        attempt + 1,
                        "; ".join(problems),
                    )
                else:
                    results[slot.id] = value
            pending = still_violating
            if not pending:
                break

        if pending:
            logger.warning(
                "text slots dropped after %d attempts (still out of bounds): %s",
                MAX_RETRIES,
                sorted(s.id for s in pending),
            )

        return TextSet(
            texts={
                sid: TextOutput(
                    value=v, overwrite_specs=run_ctx.overwrite_specs
                )
                for sid, v in results.items()
            }
        )

    async def _call_llm(
        self,
        run_ctx: RunContext,
        slots: list[TextSlot],
        *,
        prior_attempts: dict[str, str],
        prior_violations: dict[str, list[str]],
        model: str,
        fixed_context: dict[str, str],
    ) -> LLMTextResponse:
        """One structured call: closed schema keyed by the ``slots`` ids,
        prompt built from the brand brief + fixed context + slot inventory
        (+ on retry the prior attempts and the violations to fix)."""
        slot_ids = [slot.id for slot in slots]
        response_model = build_text_response_model(slot_ids)
        prompt = self._build_prompt(
            run_ctx,
            slots,
            prior_attempts=prior_attempts,
            prior_violations=prior_violations,
            fixed_context=fixed_context,
        )
        return await self._llm.complete_structured(
            [{"role": "user", "content": prompt}],
            schema=response_model,
            model=model,
        )

    @staticmethod
    def _check_bounds(value: str, slot: TextSlot) -> list[str]:
        """Return a list of human-readable violation messages (empty if
        the value satisfies every bound).

        Words are split on whitespace (the LLM never gets the exact
        regex; ``len(value.split())`` is the same rule we tell it about
        in the prompt). Characters are measured as Unicode code points
        (``len(value)``) — close enough for the display-budget purpose.
        """
        problems: list[str] = []
        words = len(value.split())
        chars = len(value)
        if words < slot.min_words:
            problems.append(
                f"too few words ({words}; min {slot.min_words})"
            )
        if words > slot.max_words:
            problems.append(
                f"too many words ({words}; max {slot.max_words})"
            )
        if chars < slot.min_chars:
            problems.append(
                f"too few characters ({chars}; min {slot.min_chars})"
            )
        if chars > slot.max_chars:
            problems.append(
                f"too many characters ({chars}; max {slot.max_chars})"
            )
        return problems

    @staticmethod
    def _build_prompt(
        run_ctx: RunContext,
        slots: list[TextSlot],
        *,
        prior_attempts: dict[str, str],
        prior_violations: dict[str, list[str]],
        fixed_context: dict[str, str],
    ) -> str:
        """Rule + brand brief + fixed context + slot inventory (+ retry block
        on retry), substituted into the one ``.md`` template
        (``safe_substitute`` tolerates a stray ``$``). The run's steering note
        (instruction + rejected attempts) is appended over the slots; fixed
        slots are listed as voice-consistency context only."""
        template = TEXT_PROMPT_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        lines = [
            f"- {slot.id}: {slot.description} | "
            f"{slot.min_words}-{slot.max_words} words, "
            f"{slot.min_chars}-{slot.max_chars} chars"
            for slot in slots
        ]
        note = run_ctx.overwrite_specs.prompt_note()
        if note:
            lines.append(f"\n{note}")
        inventory = "\n".join(lines)
        fixed_block = (
            "\n".join(
                f"- {sid}: {value!r}" for sid, value in fixed_context.items()
            )
            or "(none — fresh copy)"
        )
        if prior_attempts:
            lines = ["Your previous attempt failed length validation:", ""]
            for slot in slots:
                rejected = prior_attempts.get(slot.id)
                violations = prior_violations.get(slot.id, [])
                if rejected is None:
                    continue
                lines.append(f"- {slot.id}: rejected value {rejected!r}")
                for problem in violations:
                    lines.append(f"    - {problem}")
            lines.append("")
            lines.append(
                "Rewrite each of the slots listed below so EVERY one "
                "satisfies its hard limits. The limits are not "
                "negotiable; one character or word over still fails."
            )
            lines.append("")
            prior_attempts_block = "\n".join(lines)
        else:
            prior_attempts_block = ""
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            slots=inventory,
            fixed_context=fixed_block,
            prior_attempts_block=prior_attempts_block,
        )
