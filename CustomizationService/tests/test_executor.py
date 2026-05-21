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
_FONT = DependencyKind.FONT.value
_TEXT = DependencyKind.TEXT.value

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
_FONTS = [
    {"id": "display", "description": "headlines"},
    {"id": "body", "description": "running UI text"},
]


class _Dummy:
    """Stand-in for a paid service: nodes only store it at construction."""


def _ctx(
    tmp_path: Path,
    images: list[dict[str, Any]],
    *,
    texts: list[dict[str, Any]] | None = None,
) -> RunContext:
    payload: dict[str, Any] = {
        "id": "demo",
        "display_name": "Demo",
        "images": images,
        "colors": _COLORS,
        "fonts": _FONTS,
    }
    if texts is not None:
        payload["texts"] = texts
    app = AppFormat.model_validate(payload)
    cust = Customization.model_validate(_CUST)
    return RunContext(app, cust, tmp_path)


def _graph(ctx: RunContext) -> Any:
    return ModuleRegistry(ctx).build_all(
        llm=_Dummy(),
        image_gen=_Dummy(),
        bg_remover=_Dummy(),
        google_fonts=_Dummy(),
    )


def test_build_digraph_levels_dependencies(tmp_path: Path) -> None:
    """color + font → hero → derived: colour and font are level-0 siblings.

    No text slots → no text node in the graph (the registry skips
    constructing it; the orchestrator filters it out of the level-0
    sibling set). Exercises the empty-texts default-list path.
    """
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
    assert gens == [sorted([_COLOR, _FONT]), ["hero"], ["derived"]]
    # color is an automatic dependency of every image node; font is level-0
    # but nothing depends on it.
    assert set(graph.predecessors("hero")) == {_COLOR}
    assert set(graph.predecessors("derived")) == {_COLOR, "hero"}
    assert set(graph.predecessors(_FONT)) == set()
    # No text slots → no text node at all (not an orphan with no edges).
    assert _TEXT not in graph.nodes


def test_build_digraph_includes_text_node_when_app_has_text_slots(
    tmp_path: Path,
) -> None:
    """An app that declares text slots gets a text root in the DAG,
    level-0 alongside colour and font; nothing depends on it."""
    ctx = _ctx(
        tmp_path,
        [{"id": "hero", "description": "a hero"}],
        texts=[
            {
                "id": "booked",
                "description": "post-booking CTA",
                "max_words": 3,
                "max_chars": 20,
            }
        ],
    )
    graph = Pipeline._build_digraph(_graph(ctx))

    gens = [sorted(level) for level in nx.topological_generations(graph)]
    assert gens[0] == sorted([_COLOR, _FONT, _TEXT])
    assert set(graph.predecessors(_TEXT)) == set()
    assert set(graph.successors(_TEXT)) == set()


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
    """Build a contract-valid ColorPalette via the node's deterministic
    assembly. The executor's only contract with this object is that it
    round-trips through the writer, so we just need a fully-populated one.
    """
    from schema import ColorRole, OklchColor
    from src.modules.colors.color_models import LLMSlotResponse, LLMPalette
    from tests.colour_helpers import assemble_color_palette

    roles = {s.id: s.role for s in ctx.app.colors}

    def _oklch_for(role: ColorRole | None) -> OklchColor:
        if role is ColorRole.BACKGROUND:
            return OklchColor.from_css("oklch(15% 0.012 240)")
        if role is ColorRole.TEXT:
            return OklchColor.from_css("oklch(92% 0.01 80)")
        return OklchColor.from_css("oklch(55% 0.12 250)")

    schema = LLMPalette(
        mode=ColorMode.DARK,
        roles=roles,
        colors={
            s.id: LLMSlotResponse(
                oklch=_oklch_for(roles[s.id]),
                display_name=f"{s.id} tone",
                description=f"{s.id} colour",
            )
            for s in ctx.app.colors
        },
    )
    return assemble_color_palette(schema)


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
    # Text_set defaults to empty when no text node resolved AND the app
    # declared no text slots (no logged error, no schema break).
    assert out.text_set.texts == {}


def test_assemble_pulls_text_set_when_text_node_resolved(
    tmp_path: Path,
) -> None:
    """A resolved text node's TextSet lands on Output.text_set."""
    from schema import TextOutput, TextSet

    ctx = _ctx(
        tmp_path,
        [{"id": "hero", "description": "a hero"}],
        texts=[
            {
                "id": "booked",
                "description": "post-booking CTA",
                "max_words": 3,
                "max_chars": 20,
            }
        ],
    )
    resolved = {
        _COLOR: _palette(ctx),
        _TEXT: TextSet(texts={"booked": TextOutput(value="Locked in.")}),
    }
    out = Pipeline._assemble(ctx, resolved)

    assert set(out.text_set.texts) == {"booked"}
    assert out.text_set.texts["booked"].value == "Locked in."
