"""Seed — reconstruct the executor's start state from a saved ``output.yaml``.

A single, **slot-level** seed is the whole story: ``build_seed`` reads a saved
``Output`` into ``{slot_id: per-item output}`` for every slot present in it.
The registry hands each node its slice of that seed; the node regenerates any
declared slot absent from its slice and assembles the rest from the seed
verbatim. There is no separate "prior" or node-level skip concept — one slot
map, and the executor runs every node (a fully-seeded node just reassembles
its slots, with no LLM/provider spend).

What gets (re)generated is therefore controlled entirely by the seed: to
re-roll a present slot, a caller drops it from the seed (the ``regen`` script
pops its ``--slot`` targets); the call's single ``overwrite_specs`` steering
string is then stamped onto whatever is re-made.

This round-trip only works because every module returns its full,
self-contained output exactly as it lands in ``output.yaml`` (the
node-return-type ⇄ output-group invariant); see ``CLAUDE.md`` → *Atomic
modules*. Done-ness is YAML presence only (no on-disk file check).
"""

from __future__ import annotations

from pydantic import BaseModel

from schema import AppFormat, Output
from src.modules.base import DependencyKind

_COLOR = DependencyKind.COLOR.value
_FONT = DependencyKind.FONT.value
_TEXT = DependencyKind.TEXT.value
_ICON = DependencyKind.ICON.value


def all_slot_ids(app: AppFormat) -> set[str]:
    """Every per-slot id across all node types (colours, fonts, texts, icons,
    images) — the universe a regen can target and the seed can fill."""
    ids: set[str] = set()
    for slots in (
        app.colors,
        app.fonts,
        app.texts,
        app.icons,
        app.images,
    ):
        ids |= {s.id for s in slots}
    return ids


def node_slots(app: AppFormat) -> dict[str, set[str]]:
    """Node key → the slot ids it owns (atomic node: its inventory; per-slot
    node: just itself). The colour and font roots always exist (possibly with
    no slots); text/icon only when declared. The registry uses this to give
    each node its slice of the slot-level seed."""
    slots: dict[str, set[str]] = {
        _COLOR: {s.id for s in app.colors},
        _FONT: {s.id for s in app.fonts},
    }
    if app.texts:
        slots[_TEXT] = {s.id for s in app.texts}
    if app.icons:
        slots[_ICON] = {s.id for s in app.icons}
    for s in app.images:
        slots[s.id] = {s.id}
    return slots


def build_seed(app: AppFormat, output: Output) -> dict[str, BaseModel]:
    """Map a saved ``Output`` to ``{slot_id: per-item output}`` for every slot
    present in it.

    The seed is the sole control of what's (re)generated: a node re-makes any
    declared slot absent from its seed. A slot missing from the saved output
    is simply absent here (nothing to seed → it generates). To force a present
    slot to re-roll, the caller drops it from this map (the ``regen`` script
    pops its ``--slot`` targets). ``all_slot_ids(app) - seed.keys()`` is the
    set that will be (re)generated.
    """
    seed: dict[str, BaseModel] = {}

    def _take(slots: list, group: dict[str, BaseModel]) -> None:
        for slot in slots:
            if slot.id in group:
                seed[slot.id] = group[slot.id]

    _take(app.colors, output.color_set.colors)
    _take(app.fonts, output.font_set.fonts)
    _take(app.texts, output.text_set.texts)
    _take(app.icons, output.icon_set.icons)
    _take(app.images, output.image_set.images)
    return seed
