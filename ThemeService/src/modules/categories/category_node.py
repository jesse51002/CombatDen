"""CategoryNode — the classification graph node: file this run into one of
the app's declared ``categories``.

A level-0 sibling of ``ColorNode``, ``FontNode``, ``TextNode`` and
``IconNode``: no dependencies, so it runs in parallel with the other roots at
the top of the DAG and costs the run no wall-clock time. Like them it springs
from the brand brief alone — the classification reads the design name and the
brief, never the resolved colours or images.

Being a node (rather than a bolt-on step) is what makes the run's category
behave like everything else the pipeline produces: ``expand`` fills it in on a
run that lacks one, ``regen --slot category`` re-rolls it, a fully-seeded run
returns it with no spend, and a failure here skips only itself.

``run()`` is a thin one-step delegation to ``CategorySelectionService`` —
classification has no math step, so the selection IS the resolution. The node
only owns the dependency-graph contract (key, deps); the constants
(``CATEGORY_MODEL``, the prompt path) live in the selection service.
"""

from __future__ import annotations

from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.categories.category_models import CategoryOutput
from src.modules.categories.category_selection_service import (
    CATEGORY_MODEL,
    CategorySelectionService,
)
from src.shared.interfaces.llm_client import LLMClient

# The node's single pseudo-slot id — a run's classification is one run-wide
# value, not a per-slot inventory, so the node declares one slot named after
# its own graph key. That is what puts it in the slot-level seed keyspace.
CATEGORY_SLOT_ID = DependencyKind.CATEGORY.value


class CategoryNode(Node):
    """The classification node. ``run() -> CategoryOutput``. No dependencies."""

    def __init__(
        self,
        run_ctx: RunContext,
        *,
        llm: LLMClient,
        seed: dict[str, CategoryOutput] | None = None,
    ) -> None:
        super().__init__(
            run_ctx,
            key=DependencyKind.CATEGORY.value,
            deps=frozenset(),
            declared_slots={CATEGORY_SLOT_ID},
            seed=seed,
        )
        self._selection = CategorySelectionService(llm)

    async def run(self, *, model: str = CATEGORY_MODEL) -> CategoryOutput:
        """One LLM call picks this run's category; the app's declared
        vocabulary constrains it inside the existing structured-output retry
        loop.

        Fresh run (empty seed): classify. Reopen: a saved run that is already
        classified seeds this node done, so ``expand`` re-spends nothing —
        while a run that never had a category (or whose stamp went stale
        against a changed vocabulary) is left unseeded and gets classified for
        free on the same pass. ``regen --slot category`` drops the seed to
        force a re-roll, optionally steered by ``--spec``.
        """
        dirty = self.dirty()
        self.regenerated = dirty
        if not dirty:
            return self.seed[CATEGORY_SLOT_ID]  # type: ignore[return-value]
        return await self._selection.resolve(self._run_ctx, model=model)
