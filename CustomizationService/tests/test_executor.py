"""DAG executor tests (no network): graph build, leveling, assembly."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

import networkx as nx
import pytest
import yaml

from schema import (
    AppFormat,
    ColorMode,
    ColorOutput,
    ColorPalette,
    Customization,
    ExpansionCostLog,
    ExpansionEntry,
    ExpansionKind,
    FontOutput,
    FontSet,
    IconOutput,
    IconSet,
    ImageOutput,
    ImageSet,
    LottieOutput,
    LottieSet,
    NodeOutput,
    Output,
    OverwriteSpecs,
    RunCost,
    TextOutput,
)
from src.core.errors import GraphError
from src.core.run_context import RunContext
from src.executor.orchestrator import Pipeline
from src.executor.registry import ModuleRegistry
from src.executor.writer import Writer
from src.executor.seed import all_slot_ids, build_seed, node_slots
from src.modules.base import DependencyKind
from src.modules.colors.color_node import ColorNode

_COLOR = DependencyKind.COLOR.value
_FONT = DependencyKind.FONT.value
_TEXT = DependencyKind.TEXT.value
_ICON = DependencyKind.ICON.value

# Committed demo fixture: a real (partial) run — colour + one image done,
# fonts/texts/icons/lotties declared in app.yaml but absent from output.yaml.
_DEMO_DIR = Path(__file__).resolve().parent / "data" / "apps" / "demo"


def _demo_app() -> AppFormat:
    return AppFormat.model_validate(
        yaml.safe_load((_DEMO_DIR / "app.yaml").read_text())
    )


def _demo_output() -> Output:
    return Output.model_validate(
        yaml.safe_load((_DEMO_DIR / "default" / "output.yaml").read_text())
    )

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
    icons: list[dict[str, Any]] | None = None,
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
    if icons is not None:
        payload["icons"] = icons
    app = AppFormat.model_validate(payload)
    cust = Customization.model_validate(_CUST)
    return RunContext(app, cust, tmp_path)


def _graph(ctx: RunContext) -> Any:
    return ModuleRegistry(ctx).build_all(
        llm=_Dummy(),
        image_gen=_Dummy(),
        bg_remover=_Dummy(),
        google_fonts=_Dummy(),
        icon_catalog=_Dummy(),
        icon_generator=_Dummy(),
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
    # No icon slots → no icon node either (same skip path).
    assert _ICON not in graph.nodes


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


def test_build_digraph_includes_icon_node_when_app_has_icon_slots(
    tmp_path: Path,
) -> None:
    """An app that declares icon slots gets an icon root in the DAG,
    level-0 alongside colour and font (no colour dependency — icons are
    monochrome); nothing depends on it."""
    ctx = _ctx(
        tmp_path,
        [{"id": "hero", "description": "a hero"}],
        icons=[
            {"id": "home_tab", "description": "home navigation tab"},
            {"id": "search_action", "description": "open search"},
        ],
    )
    graph = Pipeline._build_digraph(_graph(ctx))

    gens = [sorted(level) for level in nx.topological_generations(graph)]
    assert gens[0] == sorted([_COLOR, _FONT, _ICON])
    assert set(graph.predecessors(_ICON)) == set()
    assert set(graph.successors(_ICON)) == set()


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


# --- expand: seed reconstruction (src/executor/seed.py) --------------------


def test_node_slots_mirrors_built_graph(tmp_path: Path) -> None:
    """``node_slots`` keys equal the node keys the registry builds, and the
    union of their slot ids is exactly ``all_slot_ids``."""
    app = _demo_app()
    ctx = RunContext(app, Customization.model_validate(_CUST), tmp_path)
    built = {n.key for n in _all_nodes(_graph(ctx))}
    ns = node_slots(app)
    assert set(ns) == built
    assert set().union(*ns.values()) == all_slot_ids(app)
    assert ns[_COLOR] == {"primary", "background", "text", "accent"}
    assert ns[_FONT] == {"display", "body"}
    assert ns["hero"] == {"hero"}


def test_build_seed_is_slot_level() -> None:
    """A saved run with the colours + one image done seeds exactly those
    SLOTS (per-item outputs verbatim); every absent slot is left to make."""
    app, output = _demo_app(), _demo_output()
    seed = build_seed(app, output)

    assert set(seed) == {"primary", "background", "text", "accent", "hero"}
    # Seeded values are the saved per-item models verbatim.
    assert seed["primary"] is output.color_set.colors["primary"]
    assert seed["hero"] is output.image_set.images["hero"]
    # To-(re)generate is the slot complement: the absent fonts/texts/icons/
    # lotties.
    assert all_slot_ids(app) - seed.keys() == {
        "display", "body",
        "booked_screen", "cancel_cta", "home_greeting",
        "home_tab", "search_action", "celebration_badge",
        "onboarding_pulse", "streak_reveal",
    }


def test_dropping_a_seed_slot_makes_it_dirty(tmp_path: Path) -> None:
    """Dropping a slot from the seed is what marks it for re-roll: the node's
    dirty set is exactly the declared slots absent from its seed, so the
    dropped slot is dirty and its siblings (still seeded) are preserved."""
    ctx = _ctx(tmp_path, [{"id": "hero", "description": "a hero"}])
    palette = _palette(ctx)
    seed = {  # everything present except 'primary' (dropped → re-roll)
        sid: palette.colors[sid]
        for sid in ("background", "text", "accent")
    }
    node = ColorNode(ctx, llm=_Dummy(), seed=seed)
    assert node.dirty() == {"primary"}


def test_expansion_cost_log_round_trips() -> None:
    """The expand spend ledger serializes and reloads unchanged, and an
    absent/empty file validates as an empty log."""
    log = ExpansionCostLog(
        expansions=[
            ExpansionEntry(
                expanded_at="20260524T000000Z",
                generated=["display", "primary"],
                cost=RunCost(
                    total=0.1, llm=0.05, image_generation=0.05,
                    background_removal=0.0,
                ),
            )
        ]
    )
    raw = yaml.safe_dump(log.model_dump(mode="json"))
    assert ExpansionCostLog.model_validate(yaml.safe_load(raw)) == log
    assert ExpansionCostLog.model_validate({}) == ExpansionCostLog()


# --- per-slot override recording (NodeOutput) + steering plumbing ----------


def test_per_item_outputs_inherit_node_output() -> None:
    """All six per-item output models carry the shared overwrite_specs."""
    for model in (
        ColorOutput,
        FontOutput,
        TextOutput,
        IconOutput,
        ImageOutput,
        LottieOutput,
    ):
        assert issubclass(model, NodeOutput)


def test_node_output_back_compat_and_validators() -> None:
    """An old per-item dict (no overwrite_specs) validates to ""; the field
    round-trips; and a subclass's own validator still fires."""
    # Back-compat: pre-feature output.yaml entries lack the field → empty.
    old = ImageOutput.model_validate({"path": "/x/y.png", "prompt": "p"})
    assert old.overwrite_specs == OverwriteSpecs()
    # A bare string coerces to OverwriteSpecs(specs=...); the field round-trips.
    stamped = TextOutput(value="hi", overwrite_specs="make it punchier")
    assert stamped.overwrite_specs.specs == "make it punchier"
    assert (
        TextOutput.model_validate(stamped.model_dump()).overwrite_specs.specs
        == "make it punchier"
    )
    # Inheriting NodeOutput did not suppress the subclass validator.
    with pytest.raises(ValueError, match="prompt"):
        ImageOutput(path="/x/y.png", prompt="   ")


def test_expansion_kind_resilience() -> None:
    """Unknown/missing kind degrades to UNKNOWN; known values map."""
    assert ExpansionKind.coerce("expand") is ExpansionKind.EXPAND
    assert ExpansionKind.coerce("bogus") is ExpansionKind.UNKNOWN
    cost = {
        "total": 0.0,
        "llm": 0.0,
        "image_generation": 0.0,
        "background_removal": 0.0,
    }
    bogus = ExpansionEntry.model_validate(
        {"kind": "bogus", "expanded_at": "x", "cost": cost}
    )
    assert bogus.kind is ExpansionKind.UNKNOWN
    missing = ExpansionEntry.model_validate({"expanded_at": "x", "cost": cost})
    assert missing.kind is ExpansionKind.UNKNOWN
    regen = ExpansionEntry.model_validate(
        {"kind": "regenerate", "expanded_at": "x", "cost": cost}
    )
    assert regen.kind is ExpansionKind.REGENERATE


def test_build_all_threads_specs_seed_and_declared(tmp_path: Path) -> None:
    """build_all hands every node the one steering object and the seed slice
    for the slots it owns; each node derives its dirty set from declared minus
    its seed slice."""
    ctx = _ctx(tmp_path, [{"id": "hero", "description": "a hero"}])
    palette = _palette(ctx)
    specs = OverwriteSpecs(specs="warmer")
    graph = ModuleRegistry(ctx).build_all(
        llm=_Dummy(),
        image_gen=_Dummy(),
        bg_remover=_Dummy(),
        google_fonts=_Dummy(),
        icon_catalog=_Dummy(),
        icon_generator=_Dummy(),
        overwrite_specs=specs,
        seed={  # 'primary' dropped → it's the only dirty colour slot
            "background": palette.colors["background"],
            "text": palette.colors["text"],
            "accent": palette.colors["accent"],
        },
    )
    assert graph.color.declared_slots == {
        "primary", "background", "text", "accent"
    }
    assert graph.color.overwrite_specs is specs  # one object, every node
    assert graph.color.dirty() == {"primary"}
    assert graph.font.overwrite_specs is specs
    assert graph.font.seed == {}  # no font slot in the seed
    hero = next(n for n in graph.images if n.key == "hero")
    assert hero.dirty() == {"hero"}  # image absent from seed


def _all_nodes(graph: Any) -> list[Any]:
    """Every node object on a built Graph (text/icon may be None)."""
    nodes = [graph.color, graph.font, *graph.images, *graph.lotties]
    if graph.text is not None:
        nodes.append(graph.text)
    if graph.icon is not None:
        nodes.append(graph.icon)
    return nodes


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


# --- Writer content-version stamping ------------------------------------


def test_content_version_hashes_bytes(tmp_path: Path) -> None:
    """``_content_version`` is sha256[:12] of the bytes: deterministic,
    change-sensitive, and "" for an absent file."""
    f = tmp_path / "a.png"
    f.write_bytes(b"one")
    assert (
        Writer._content_version(f)
        == hashlib.sha256(b"one").hexdigest()[:12]
    )
    # Identical bytes hash identically (stable URL for an unchanged asset).
    g = tmp_path / "b.png"
    g.write_bytes(b"one")
    assert Writer._content_version(g) == Writer._content_version(f)
    # Changed bytes change the hash (the cache busts).
    f.write_bytes(b"two")
    assert Writer._content_version(f) != Writer._content_version(g)
    # Absent file → empty (URL stays unversioned).
    assert Writer._content_version(tmp_path / "missing.png") == ""


def test_stamp_versions_fingerprints_each_served_asset(
    tmp_path: Path,
) -> None:
    """``_stamp_versions`` fingerprints the served file for every image,
    icon and lottie slot; a slot whose file is missing stays unversioned."""
    ctx = _ctx(tmp_path, [{"id": "hero", "description": "a hero"}])

    png = b"\x89PNG fake hero bytes"
    svg = b"<svg>home</svg>"
    lottie = b'{"v":"5.7","layers":[]}'
    Path(str(ctx.image_path("hero"))).write_bytes(png)
    Path(str(ctx.icon_path("nav_home"))).write_bytes(svg)
    Path(str(ctx.lottie_path("cel"))).write_bytes(lottie)

    out = Output(
        app="demo",
        display_name="Demo",
        design_name="Demo",
        color_set=_palette(ctx),
        image_set=ImageSet(
            images={
                "hero": ImageOutput(path=ctx.image_path("hero"), prompt="p"),
                # No file on disk → stays unversioned.
                "ghost": ImageOutput(
                    path=ctx.image_path("ghost"), prompt="p"
                ),
            }
        ),
        icon_set=IconSet(
            icons={
                "nav_home": IconOutput(
                    path=ctx.icon_path("nav_home"),
                    icon_set="lucide",
                    icon_name="home",
                    icon_key="nav_home",
                )
            }
        ),
        lottie_set=LottieSet(
            lotties={
                "cel": LottieOutput(
                    preset_id="p",
                    preset_file="p.json",
                    display_name="Cel",
                    path=ctx.lottie_path("cel"),
                    speed=1.0,
                    region_roles={},
                )
            }
        ),
    )

    Writer()._stamp_versions(out, ctx)

    assert (
        out.image_set.images["hero"].version
        == hashlib.sha256(png).hexdigest()[:12]
    )
    assert out.image_set.images["ghost"].version == ""
    assert (
        out.icon_set.icons["nav_home"].version
        == hashlib.sha256(svg).hexdigest()[:12]
    )
    assert (
        out.lottie_set.lotties["cel"].version
        == hashlib.sha256(lottie).hexdigest()[:12]
    )
