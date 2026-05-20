"""TextNode — the text graph node: rewrite every text slot in one batched
LLM call (with a per-slot length-bounds retry inside the service).

A level-0 sibling of ``ColorNode`` and ``FontNode``: no dependencies,
runs in parallel with the colour and font roots at the top of the
DAG. All three spring from the brand brief and don't need each other.
Text vibe comes from the design direction; the deterministic length
contract per slot rides in the slot's own ``min_/max_`` fields.

``run()`` is a thin one-step delegation to ``TextGenerationService`` —
text has no math step (no contrast / no derivations), so the
generation IS the resolution. The node only owns the dependency-graph
contract (key, deps); constants (``TEXT_MODEL``, prompt path,
``MAX_RETRIES``) live in the generation service.
"""

from __future__ import annotations

from schema import TextSet
from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.texts.text_generation_service import (
    TEXT_MODEL,
    TextGenerationService,
)
from src.shared.interfaces.llm_client import LLMClient


class TextNode(Node):
    """The text node. ``run() -> TextSet``. No dependencies."""

    def __init__(self, run_ctx: RunContext, *, llm: LLMClient) -> None:
        super().__init__(
            run_ctx, key=DependencyKind.TEXT.value, deps=frozenset()
        )
        self._generation = TextGenerationService(llm)

    async def run(self, *, model: str = TEXT_MODEL) -> TextSet:
        """Resolve every text slot via the generation service's per-slot
        retry loop. The result may be partial: any slot that never
        satisfied its length bounds within the retry budget is omitted
        from ``TextSet.texts`` and the MobileApp falls back to its
        bundled default."""
        return await self._generation.resolve(self._run_ctx, model=model)
