"""FormatNode — the format graph node: pick one value for every format
slot the app declares, in one batched LLM call.

A level-0 sibling of ``ColorNode``, ``FontNode``, ``TextNode``,
``IconNode`` and ``CategoryNode``: no dependencies, so it runs in parallel
with the other roots at the top of the DAG and costs the run no
wall-clock time beside colour and font. Like them it springs from the
brand brief alone — an arrangement is chosen from what the brand IS,
never from the resolved colours or images.

Being a node (rather than a bolt-on step) is what makes a run's formats
behave like everything else the pipeline produces: ``expand`` fills them
in on a run that lacks them, ``regen --slot <format slot>`` re-rolls one
(harmonised against the rest, which are shown as fixed context), a
fully-seeded run returns them with no spend, and a failure here skips
only itself — the client then renders the arrangement it ships.

``run()`` is a thin one-step delegation to ``FormatSelectionService`` —
format selection has no math step and no deterministic post-check, so the
selection IS the resolution. The node only owns the dependency-graph
contract (key, deps, declared slots); the constants (``FORMAT_MODEL``,
the prompt path) live in the selection service.
"""

from __future__ import annotations

from schema import FormatOutput, FormatSet
from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.formats.format_selection_service import (
    FORMAT_MODEL,
    FormatSelectionService,
)
from src.shared.interfaces.llm_client import LLMClient


class FormatNode(Node):
    """The format node. ``run() -> FormatSet``. No dependencies."""

    def __init__(
        self,
        run_ctx: RunContext,
        *,
        llm: LLMClient,
        seed: dict[str, FormatOutput] | None = None,
    ) -> None:
        super().__init__(
            run_ctx,
            key=DependencyKind.FORMAT.value,
            deps=frozenset(),
            declared_slots={slot.id for slot in run_ctx.app.formats},
            seed=seed,
        )
        self._selection = FormatSelectionService(llm)

    async def run(self, *, model: str = FORMAT_MODEL) -> FormatSet:
        """Resolve the dirty format slots in one call; each slot's own
        declared vocabulary constrains it inside the existing
        structured-output retry loop.

        Fresh run (empty seed): pick every slot together, so the whole
        arrangement is one coherent decision. Reopen: a saved run whose
        formats are already chosen seeds this node done, so ``expand``
        re-spends nothing — while a run that never had them (or whose
        value went stale against a changed vocabulary) is left unseeded
        and gets picked for free on the same pass. ``regen --slot
        <format slot>`` drops that slot from the seed to force a re-roll,
        optionally steered by ``--spec``, with the untouched slots shown
        as fixed context and kept verbatim.
        """
        dirty = self.dirty()
        self.regenerated = dirty
        if not dirty:
            return FormatSet(formats=dict(self.seed))  # type: ignore[arg-type]
        regenerated = await self._selection.resolve(
            self._run_ctx,
            model=model,
            only=dirty,
            fixed=self.seed,  # type: ignore[arg-type]
        )
        return FormatSet(formats={**self.seed, **regenerated.formats})
