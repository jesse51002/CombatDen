"""DAG executor tests (no network): graph build, leveling, assembly."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import networkx as nx
import pytest

from schema import (
    AppFormat,
    ColorMode,
    ColorPalette,
    Customization,
    ImageOutput,
)
from src.core.errors import GraphError
from src.core.run_context import RunContext
from src.executor.orchestrator import Pipeline
from src.executor.registry import ModuleRegistry
from src.modules.base import DependencyKind

_COLOR = DependencyKind.COLOR.value

_CUST: dict[str, Any] = {
    "design_direction": {
        "name": "Demo",
        "short_desc": "short",
        "long_desc": "long",
    },
    "colors_direction": {"description": "calm", "mode": "dark"},
}
_COLORS = [
    {"id": "primary", "description": "primary"},
    {"id": "background", "description": "bg", "role": "background"},
    {"id": "text", "description": "text", "role": "text"},
    {"id": "accent", "description": "accent"},
]


class _Dummy:
    """Stand-in for a paid service: nodes only store it at construction."""


def _ctx(tmp_path: Path, images: list[dict[str, Any]]) -> RunContext:
    app = AppFormat.model_validate(
        {
            "id": "demo",
            "display_name": "Demo",
            "images": images,
            "colors": _COLORS,
        }
    )
    cust = Customization.model_validate(_CUST)
    return RunContext(app, cust, tmp_path)


def _graph(ctx: RunContext) -> Any:
    return ModuleRegistry(ctx).build_all(
        llm=_Dummy(), image_gen=_Dummy(), bg_remover=_Dummy()
    )


def test_build_digraph_levels_dependencies(tmp_path: Path) -> None:
    """color → hero → derived: each on its own topological generation."""
    ctx = _ctx(
        tmp_path,
        [
            {"id": "hero", "description": "a hero"},
            {
                "id": "derived",
                "description": "builds on hero",
                "depends_on": ["hero"],
            },
        ],
    )
    graph = Pipeline._build_digraph(_graph(ctx))

    gens = [sorted(level) for level in nx.topological_generations(graph)]
    assert gens == [[_COLOR], ["hero"], ["derived"]]
    # color is an automatic dependency of every image node.
    assert set(graph.predecessors("hero")) == {_COLOR}
    assert set(graph.predecessors("derived")) == {_COLOR, "hero"}


def test_build_digraph_rejects_cycle(tmp_path: Path) -> None:
    """A depends_on cycle is caught at graph build, before any node runs."""
    ctx = _ctx(
        tmp_path,
        [
            {"id": "a", "description": "a", "depends_on": ["b"]},
            {"id": "b", "description": "b", "depends_on": ["a"]},
        ],
    )
    with pytest.raises(GraphError, match="cycle"):
        Pipeline._build_digraph(_graph(ctx))


def test_build_digraph_rejects_unknown_producer(tmp_path: Path) -> None:
    """A dep with no producing node is rejected (defense-in-depth)."""
    ctx = _ctx(tmp_path, [{"id": "hero", "description": "a hero"}])
    graph = _graph(ctx)
    graph.images[0].deps = frozenset({_COLOR, "ghost"})
    with pytest.raises(GraphError, match="ghost"):
        Pipeline._build_digraph(graph)


def _palette(ctx: RunContext) -> ColorPalette:
    from schema import ColorOutput

    return ColorPalette(
        mode=ColorMode.DARK,
        colors={
            s.id: ColorOutput(
                oklch="oklch(55% 0.12 250)",
                display_name=f"{s.id} tone",
                description=f"{s.id} colour",
            )
            for s in ctx.app.colors
        },
    )


def _img_out(ctx: RunContext, slot_id: str) -> ImageOutput:
    return ImageOutput(
        path=ctx.image_path(slot_id), prompt="p", complexity=None
    )


def test_assemble_partial_keeps_finished_work(tmp_path: Path) -> None:
    """A failed node drops only itself: the rest is still written."""
    ctx = _ctx(
        tmp_path,
        [
            {"id": "hero", "description": "a hero"},
            {"id": "other", "description": "another"},
        ],
    )
    resolved = {
        _COLOR: _palette(ctx),
        "hero": _img_out(ctx, "hero"),
        # "other" failed → absent from resolved
    }
    out = Pipeline._assemble(ctx, resolved)

    assert set(out.color_set.colors) == {
        "primary",
        "background",
        "text",
        "accent",
    }
    assert set(out.image_set.images) == {"hero"}  # 'other' omitted


def test_assemble_color_failure_yields_valid_empty_output(
    tmp_path: Path,
) -> None:
    """Colour node failing → near-empty but schema-valid Output."""
    ctx = _ctx(tmp_path, [{"id": "hero", "description": "a hero"}])
    out = Pipeline._assemble(ctx, {})

    assert out.app == "demo"
    assert out.color_set.colors == {}
    assert out.color_set.mode == ColorMode.DARK
    assert out.image_set.images == {}
