"""Pipeline — the DAG executor: build the graph, run each level, assemble.

Replaces the old sequential per-slot loop. Nodes are levelled
topologically (networkx); the nodes in a level run concurrently behind a
single run-wide semaphore that caps in-flight modules at
``MAX_CONCURRENT_MODULES`` — the work is I/O-bound but image providers
rate-limit hard, so a level is not unleashed unbounded. Fault-tolerant:
a node failure never aborts the run — only its
transitive dependents are skipped, and whatever resolved is written. The
paid services are returned alongside the output so the writer can total
their running cost.

The executor is also where a run is **observed**. It owns iteration, so it
is the only place that knows a level started, a node started, a node took
4.2 s, or the whole run took 6 minutes — and per *Atomic modules* it is the
only place allowed to know: modules carry no progress code whatsoever. Every
node is timed with ``perf_counter`` (logged either way) and, when the caller
passes a ``ProgressSink``, reported as a ``ProgressEvent``. With no sink the
run behaves exactly as it always has.
"""

from __future__ import annotations

import asyncio
import logging
import shutil
from dataclasses import dataclass
from time import perf_counter

import networkx as nx
from pydantic import BaseModel

from schema import (
    ColorPalette,
    FontSet,
    FormatSet,
    IconSet,
    ImageSet,
    Output,
    TextSet,
)
from src.core.config import settings
from src.core.errors import GraphError, PipelineError
from src.core.run_context import RunContext
from src.executor.progress_event import ProgressEvent, ProgressEventKind
from src.executor.progress_sink import ProgressSink
from src.executor.registry import Graph, ModuleRegistry
from src.modules.base import DependencyKind, Node
from src.shared.interfaces.background_remover import BackgroundRemover
from src.shared.interfaces.google_fonts_catalog import GoogleFontsCatalog
from src.shared.interfaces.icon_set_catalog import IconSetCatalog
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient
from src.shared.services.background_remover import RecraftBackgroundRemover
from src.shared.services.google_fonts_catalog import HttpxGoogleFontsCatalog
from src.shared.services.litellm_image_generator import LiteLLMImageGenerator
from src.shared.services.llm_client import LiteLLMClient
from src.shared.services.local_icon_set_catalog import LocalIconSetCatalog
from src.shared.services.recraft_icon_generator import RecraftIconGenerator

logger = logging.getLogger(__name__)

# Most modules allowed in flight at once. The work is I/O-bound, but
# image providers rate-limit hard — an unbounded level can stampede
# them. One semaphore for the whole run caps concurrency here; levels
# stay sequential regardless.
MAX_CONCURRENT_MODULES = 5


@dataclass(frozen=True)
class PipelineResult:
    """One run's assembled output plus the paid services that produced it.

    The services carry their own running ``cost``; the writer reads them
    to aggregate the run total. A dataclass (not a Pydantic model) so it
    holds the live service instances without per-field isinstance
    enforcement.

    ``generated`` is the set of slot ids this pass actually (re)made — the
    union of each node's ``regenerated``. For a full run that is every slot;
    for a reopen pass it is only the dirty (steered or missing) slots, the
    rest being returned from the seed untouched. Because the paid services are
    freshly constructed per ``run()``, their accumulated cost is exactly the
    spend for ``generated`` — what the expand/regen writer records in
    ``expansion_cost.yaml``.
    """

    output: Output
    llm: LLMClient
    image_gen: ImageGenerator
    bg_remover: BackgroundRemover
    icon_gen: ImageGenerator
    generated: frozenset[str]

    @property
    def total_cost(self) -> float:
        """Raw sum of every paid service's running cost, unrounded.

        The one place that adds the four services up, so a live progress
        readout and the artifact can't drift on *what* is counted. The
        artifact's rounded, per-service ``RunCost`` breakdown stays the
        Writer's job (``Writer._run_cost``).
        """
        return (
            self.llm.cost
            + self.image_gen.cost
            + self.bg_remover.cost
            + self.icon_gen.cost
        )


class Pipeline:
    """Runs one customization end to end (configuration via settings)."""

    @staticmethod
    def _build_digraph(node_set: Graph) -> nx.DiGraph:
        """Assemble + validate the dependency DiGraph (fail fast, no spend).

        Edges run dependency → dependent. Raises ``GraphError`` if a node
        depends on a key no node produces, or if the edges form a cycle —
        both *before* any node runs.
        """
        graph: nx.DiGraph = nx.DiGraph()
        # ``text`` / ``icon`` / ``category`` / ``format`` are optional: an app
        # with no copy overrides, no icon overrides, no declared
        # classification vocabulary, or no switchable arrangements doesn't get
        # that node, so it's filtered out of the level-0 sibling set rather
        # than producing a no-op root.
        nodes = [
            node_set.color,
            node_set.font,
            *node_set.images,
        ]
        if node_set.text is not None:
            nodes.append(node_set.text)
        if node_set.icon is not None:
            nodes.append(node_set.icon)
        if node_set.category is not None:
            nodes.append(node_set.category)
        if node_set.format is not None:
            nodes.append(node_set.format)
        for node in nodes:
            graph.add_node(node.key, node=node)
        known = {node.key for node in nodes}
        for node in nodes:
            for dep in node.deps:
                if dep not in known:
                    raise GraphError(
                        f"node {node.key!r} depends on {dep!r} "
                        "which no node produces"
                    )
                graph.add_edge(dep, node.key)
        if not nx.is_directed_acyclic_graph(graph):
            raise GraphError(f"dependency cycle: {nx.find_cycle(graph)}")
        return graph

    @staticmethod
    async def _emit(
        progress: ProgressSink | None, event: ProgressEvent
    ) -> None:
        """Hand one event to the sink, if there is one. The single place
        the optional-sink check lives, so no call site repeats it."""
        if progress is None:
            return
        await progress.emit(event)

    @staticmethod
    async def _run_capped(
        node: Node,
        sem: asyncio.Semaphore,
        *,
        level: int,
        image_slot: str | None,
        progress: ProgressSink | None,
    ) -> BaseModel:
        """Run one node while holding ``sem`` — bounds level concurrency
        to ``MAX_CONCURRENT_MODULES`` without any module change — and time it.

        The clock starts *after* the semaphore is acquired, so the reported
        elapsed is the node's own work, not the queueing behind a full level.
        For the same reason ``NODE_STARTED`` is emitted here rather than at
        level assembly: with a cap of ``MAX_CONCURRENT_MODULES`` a 10-node
        level does not start 10 nodes at once, and a watcher that was told
        otherwise would show ten spinners for work that hasn't begun.

        Failures re-raise unchanged. The level's ``asyncio.gather`` still
        collects them with ``return_exceptions=True`` and the existing
        skip-the-dependents logic is untouched — this only reports on the way
        past.
        """
        async with sem:
            await Pipeline._emit(
                progress,
                ProgressEvent(
                    kind=ProgressEventKind.NODE_STARTED,
                    node=node.key,
                    image_slot=image_slot,
                    level=level,
                ),
            )
            started = perf_counter()
            try:
                result = await node.run()
            except Exception as exc:
                elapsed = perf_counter() - started
                logger.info(
                    "node %s failed after %.2fs", node.key, elapsed
                )
                await Pipeline._emit(
                    progress,
                    ProgressEvent(
                        kind=ProgressEventKind.NODE_FAILED,
                        node=node.key,
                        image_slot=image_slot,
                        level=level,
                        ok=False,
                        elapsed_seconds=elapsed,
                        error=f"{type(exc).__name__}: {exc}",
                    ),
                )
                raise
            elapsed = perf_counter() - started
            logger.info("node %s finished in %.2fs", node.key, elapsed)
            await Pipeline._emit(
                progress,
                ProgressEvent(
                    kind=ProgressEventKind.NODE_FINISHED,
                    node=node.key,
                    image_slot=image_slot,
                    level=level,
                    ok=True,
                    elapsed_seconds=elapsed,
                ),
            )
            return result

    @staticmethod
    def _overwrite_existing(run_ctx: RunContext) -> None:
        """Clear a run dir's produced artifacts before a full overwrite re-run.

        Only the *produced* artifacts are removed — ``output.yaml``,
        ``expansion_cost.yaml`` and the ``images/`` / ``final_images/`` /
        ``icons/`` trees; the run's editable *inputs*
        (``app.yaml``, ``customization.yaml``) are kept, because the run
        regenerates from them. A fresh run dir (no produced artifacts) is a
        no-op — nothing to clear.

        Two safety rails make this destructive step impossible to point at the
        wrong place, and both are **path identity**, never a path *name*:

        1. The resolved run dir must sit inside the resolved
           ``run_ctx.out_root`` — the output root this process was actually
           configured with.
        2. Every target is a path *derived from* ``run_ctx`` (never an
           arbitrary path) and must resolve strictly inside that same resolved
           run dir.

        Either failing aborts the run rather than deleting anything.

        Rail 1 is identity-based because a name check is not a guard at all
        here. In every git worktree the per-run dirs under ``apps/<app_id>/``
        are **symlinks into the primary checkout**, so ``.resolve()`` lands on
        a directory whose grandparent is *also* named ``apps`` — a name check
        passes and the ``rmtree`` below deletes the other checkout's real run.
        Those runs are gitignored (``apps/*/*/``), so nothing is recoverable.
        Comparing against the configured root instead makes the escape
        impossible: a run dir that resolves outside the root this process was
        pointed at is refused, wherever it points.
        """
        asset_dirs = (
            run_ctx.image_dir,
            run_ctx.final_image_dir,
            run_ctx.icon_dir,
        )
        produced = [
            run_ctx.output_path(),
            run_ctx.expansion_cost_path(),
            *asset_dirs,
        ]
        has_artifacts = run_ctx.output_path().exists() or any(
            d.is_dir() and any(d.iterdir()) for d in asset_dirs
        )
        if not has_artifacts:
            return

        run_dir = run_ctx.run_dir.resolve()
        out_root = run_ctx.out_root.resolve()
        # Identity, not name: the run dir must resolve INSIDE the output root
        # this process was configured with. A symlinked run dir (every git
        # worktree) resolves into the other checkout and is refused here.
        if not run_dir.is_relative_to(out_root):
            raise PipelineError(
                f"refusing to overwrite {run_dir}: it resolves outside this "
                f"run's output root {out_root} (safety guard). A run dir that "
                "is a symlink into another checkout resolves this way — clear "
                "it from the checkout that owns it."
            )
        logger.warning(
            "overwriting existing run %s: clearing produced artifacts and "
            "regenerating ALL slots (incl. images) from this run's brief — "
            "this spends money",
            run_dir,
        )
        for path in produced:
            resolved = path.resolve()
            if run_dir not in resolved.parents:
                # Rail 2. Already identity-based (both sides are fully
                # resolved, so a symlinked target lands outside and is caught)
                # — and it now runs only once rail 1 has confirmed ``run_dir``
                # itself is inside the configured output root. Derived paths
                # are always inside run_dir; a target that isn't means
                # something is wrong — skip it rather than delete it.
                # ``in .parents`` also refuses ``resolved == run_dir``, so the
                # run dir itself can never be the rmtree target.
                logger.error(
                    "skipping clear of %s: outside run dir %s", resolved, run_dir
                )
                continue
            if resolved.is_dir():
                shutil.rmtree(resolved)
                resolved.mkdir(parents=True, exist_ok=True)
                logger.info("cleared %s/", resolved.name)
            elif resolved.exists():
                resolved.unlink()
                logger.info("cleared %s", resolved.name)

    async def run(
        self,
        run_ctx: RunContext,
        *,
        seed: dict[str, BaseModel] | None = None,
        progress: ProgressSink | None = None,
    ) -> PipelineResult:
        """Resolve every node level-by-level, assemble the ``Output``, and
        return it alongside the paid services so the writer can total
        their cost.

        Reopen-time regeneration is entirely a node concern; the executor
        stays domain-blind. ``seed`` (slot id → that slot's saved per-item
        output) is the sole control of what's re-made — a node regenerates any
        declared slot absent from its seed slice and returns the rest verbatim
        (no LLM/provider spend). The run's steering (``run_ctx.overwrite_specs``)
        is stamped onto whatever is re-made. An empty ``seed`` ⇒ every node
        regenerates every slot, a normal full run.
        ``PipelineResult.generated`` is the union of the slot ids the nodes
        actually re-made.

        ``progress`` is an optional observer (``ProgressSink``). Given one, the
        run reports itself as it happens — started, each level, each node's
        start/finish/failure with its own elapsed time, and the run total with
        its cost. Given none (the default, and what the CLI passes), nothing is
        emitted and the run behaves exactly as before. The sink is an
        interface: the executor knows nothing of HTTP, SSE or JSON.
        """
        # A full (unseeded) run pointed at an existing run dir is an in-place
        # re-run: clear its produced artifacts first so it's a clean overwrite.
        # Seeded passes (expand/regen) reopen a run to *keep* most of it, so
        # they must never clear — hence keying on the seed.
        started = perf_counter()
        if not seed:
            self._overwrite_existing(run_ctx)
        llm = LiteLLMClient()
        image_gen = LiteLLMImageGenerator()
        bg_remover = RecraftBackgroundRemover()
        icon_gen = RecraftIconGenerator()
        google_fonts: GoogleFontsCatalog = HttpxGoogleFontsCatalog(
            api_key=settings.google_fonts_api_key,
            api_url=settings.google_fonts_api_url,
            ttl_seconds=settings.google_fonts_ttl_seconds,
            request_timeout_seconds=settings.google_fonts_request_timeout_seconds,
        )
        icon_catalog: IconSetCatalog = LocalIconSetCatalog(
            root=settings.icon_sets_dir
        )

        node_set = ModuleRegistry(run_ctx).build_all(
            llm=llm,
            image_gen=image_gen,
            bg_remover=bg_remover,
            google_fonts=google_fonts,
            icon_catalog=icon_catalog,
            icon_generator=icon_gen,
            seed=seed,
        )
        graph = self._build_digraph(node_set)
        # Which node keys are per-slot IMAGE nodes, read off the built node
        # set rather than inferred from the key: exact, and app-agnostic.
        # A watcher uses this to know a slot's final_images/<slot>.png just
        # landed and can be shown.
        image_keys = {node.key for node in node_set.images}
        levels = list(nx.topological_generations(graph))

        resolved: dict[str, BaseModel] = {}
        generated: set[str] = set()
        skipped: set[str] = set()
        sem = asyncio.Semaphore(MAX_CONCURRENT_MODULES)

        await self._emit(
            progress,
            ProgressEvent(
                kind=ProgressEventKind.RUN_STARTED,
                app_id=run_ctx.app_id,
                run_id=run_ctx.run_id,
                total_levels=len(levels),
                total_nodes=graph.number_of_nodes(),
            ),
        )

        for index, generation in enumerate(levels):
            batch = [
                graph.nodes[key]["node"]
                for key in generation
                if key not in skipped
            ]
            if not batch:
                continue
            await self._emit(
                progress,
                ProgressEvent(
                    kind=ProgressEventKind.LEVEL_STARTED,
                    level=index,
                    level_nodes=sorted(node.key for node in batch),
                    total_levels=len(levels),
                ),
            )
            # Inject each node's available dependency outputs. A node that is
            # only assembling from its seed needs none; one that regenerates
            # reads them — and was skipped above if a dependency it needs
            # failed, so injecting just what resolved is safe.
            for node in batch:
                node.inputs = {
                    dep: resolved[dep]
                    for dep in node.deps
                    if dep in resolved
                }
            logger.debug(
                "running level: %s", [node.key for node in batch]
            )
            results = await asyncio.gather(
                *(
                    self._run_capped(
                        node,
                        sem,
                        level=index,
                        image_slot=(
                            node.key if node.key in image_keys else None
                        ),
                        progress=progress,
                    )
                    for node in batch
                ),
                return_exceptions=True,
            )
            for node, result in zip(batch, results):
                if isinstance(result, Exception):
                    # One bad node must not lose finished work. Skip only the
                    # dependents that would actually REGENERATE (they need the
                    # failed output); a dependent that is merely reassembling
                    # its seed needs nothing and still runs.
                    logger.warning(
                        "node %s failed (%s); skipping its regenerating "
                        "dependents",
                        node.key,
                        result,
                    )
                    skipped |= {
                        dep
                        for dep in nx.descendants(graph, node.key)
                        if graph.nodes[dep]["node"].dirty()
                    } | {node.key}
                else:
                    resolved[node.key] = result
                    generated |= node.regenerated

        output = self._assemble(run_ctx, resolved)
        result = PipelineResult(
            output=output,
            llm=llm,
            image_gen=image_gen,
            bg_remover=bg_remover,
            icon_gen=icon_gen,
            generated=frozenset(generated),
        )
        elapsed = perf_counter() - started
        logger.info(
            "run %s/%s finished in %.2fs ($%.4f, %d slot(s) generated)",
            run_ctx.app_id,
            run_ctx.run_id,
            elapsed,
            result.total_cost,
            len(result.generated),
        )
        await self._emit(
            progress,
            ProgressEvent(
                kind=ProgressEventKind.RUN_FINISHED,
                app_id=run_ctx.app_id,
                run_id=run_ctx.run_id,
                elapsed_seconds=elapsed,
                cost=result.total_cost,
                generated=sorted(result.generated),
            ),
        )
        return result

    @staticmethod
    def _assemble(
        run_ctx: RunContext, resolved: dict[str, BaseModel]
    ) -> Output:
        """Assemble the (possibly partial) ``Output`` from what resolved."""
        palette = resolved.get(DependencyKind.COLOR.value)
        if palette is None:
            # Colour node didn't resolve — emit the minimal valid shell so
            # the writer can still produce something useful. `palette` is
            # required by ColorPalette, but there's nothing to populate it
            # with when colours failed; an empty dict is the honest answer.
            palette = ColorPalette(
                mode=run_ctx.cust.colors_direction.mode,
                colors={},
                palette={},
            )
        if not palette.colors:
            logger.error(
                "colour node did not resolve — output has no colours "
                "(and therefore no images)"
            )
        font_set = resolved.get(DependencyKind.FONT.value)
        if font_set is None:
            # Font node didn't resolve — empty FontSet is the honest
            # answer (no font slots populated). Unlike colours, no other
            # node depends on it, so an empty set doesn't cascade.
            font_set = FontSet(fonts={})
            logger.error("font node did not resolve — output has no fonts")
        text_set = resolved.get(DependencyKind.TEXT.value)
        if text_set is None:
            # Text node either wasn't built (app declared no text slots —
            # the registry skipped it) or failed outright. Empty TextSet
            # is the honest answer either way; the MobileApp falls back
            # to its bundled default copy. Logging the failure is only
            # warranted when a text node was actually expected — the
            # registry skip is a normal, common case for apps without
            # copy overrides.
            text_set = TextSet(texts={})
            if run_ctx.app.texts:
                logger.error(
                    "text node did not resolve — output has no copy "
                    "overrides"
                )
        icon_set = resolved.get(DependencyKind.ICON.value)
        if icon_set is None:
            # Icon node either wasn't built (app declared no icon slots —
            # the registry skipped it) or failed outright. Empty IconSet
            # is the honest answer either way; the MobileApp falls back to
            # its bundled icons. Only log a failure when an icon node was
            # actually expected (the registry skip is the normal case for
            # apps without icon overrides).
            icon_set = IconSet(icons={})
            if run_ctx.app.icons:
                logger.error(
                    "icon node did not resolve — output has no icon "
                    "overrides"
                )
        format_set = resolved.get(DependencyKind.FORMAT.value)
        if format_set is None:
            # Format node either wasn't built (app declared no format slots —
            # the registry skipped it) or failed outright. An empty FormatSet
            # is the honest answer either way; the consuming client renders
            # the arrangement it ships. Only log a failure when a format node
            # was actually expected (the registry skip is the normal case for
            # apps with no switchable arrangements).
            format_set = FormatSet(formats={})
            if run_ctx.app.formats:
                logger.error(
                    "format node did not resolve — output has no format "
                    "overrides"
                )
        category = resolved.get(DependencyKind.CATEGORY.value)
        if category is None and run_ctx.app.categories:
            # The classification node was built (the app declares a
            # vocabulary) but failed. ``None`` is the honest answer — the
            # writer then falls back to any category the run already carried,
            # so a provider blip never drops a listed theme out of the picker.
            logger.error(
                "classification node did not resolve — output has no category"
            )
        image_set = ImageSet(
            images={
                slot.id: resolved[slot.id]
                for slot in run_ctx.app.images
                if slot.id in resolved
            }
        )
        return Output(
            app=run_ctx.app.id,
            display_name=run_ctx.app.display_name,
            design_name=run_ctx.cust.design_direction.name,
            category=category.value if category is not None else None,
            image_set=image_set,
            color_set=palette,
            font_set=font_set,
            text_set=text_set,
            icon_set=icon_set,
            format_set=format_set,
        )
