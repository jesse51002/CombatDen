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
modules*. The classification node is the one whose output is a run-wide
**scalar** rather than a group — it returns a ``CategoryOutput`` carrier whose
``value`` is the saved ``output.category``, which round-trips just as
completely. Done-ness is YAML presence only (no on-disk file check).
"""

from __future__ import annotations

from pydantic import BaseModel

from schema import AppFormat, Output
from src.modules.base import DependencyKind
from src.modules.categories.category_models import CategoryOutput

_COLOR = DependencyKind.COLOR.value
_FONT = DependencyKind.FONT.value
_TEXT = DependencyKind.TEXT.value
_ICON = DependencyKind.ICON.value
_FORMAT = DependencyKind.FORMAT.value
# The classification node's single pseudo-slot id (its own graph key): the
# run's category is one run-wide value, not a per-slot inventory, but it joins
# the same slot keyspace so it seeds, expands and regenerates like everything
# else.
_CATEGORY = DependencyKind.CATEGORY.value


def all_slot_ids(app: AppFormat) -> set[str]:
    """Every per-slot id across all node types (colours, fonts, texts, icons,
    formats, images) plus the classification pseudo-slot — the universe a
    regen can target and the seed can fill."""
    ids: set[str] = set()
    for slots in (
        app.colors,
        app.fonts,
        app.texts,
        app.icons,
        app.formats,
        app.images,
    ):
        ids |= {s.id for s in slots}
    if app.categories:
        ids.add(_CATEGORY)
    return ids


def node_slots(app: AppFormat) -> dict[str, set[str]]:
    """Node key → the slot ids it owns (atomic node: its inventory; per-slot
    node: just itself). The colour and font roots always exist (possibly with
    no slots); text/icon/format only when declared, and classification only
    when the app declares a ``categories`` vocabulary. The registry uses this
    to give each node its slice of the slot-level seed."""
    slots: dict[str, set[str]] = {
        _COLOR: {s.id for s in app.colors},
        _FONT: {s.id for s in app.fonts},
    }
    if app.texts:
        slots[_TEXT] = {s.id for s in app.texts}
    if app.icons:
        slots[_ICON] = {s.id for s in app.icons}
    if app.formats:
        slots[_FORMAT] = {s.id for s in app.formats}
    if app.categories:
        slots[_CATEGORY] = {_CATEGORY}
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

    The classification pseudo-slot seeds from the saved scalar
    ``output.category`` — but only when that value is **still in the app's
    declared vocabulary**. A run that was never classified, and a run whose
    stamp went stale against a changed ``app.yaml``, are both left unseeded, so
    an ``expand`` pass classifies them rather than carrying an unusable value
    forward (a category outside the vocabulary is skipped by the styles API
    exactly like a missing one).

    Format slots seed under the same staleness rule, per slot: a saved value
    is carried only while it is **still in that slot's declared vocabulary**.
    A slot whose vocabulary changed under it is left unseeded so an
    ``expand`` pass re-picks it, rather than carrying a token the client
    can no longer parse (which it would silently ignore, falling back to its
    shipped arrangement — a regression nobody would trace back to here).
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
    for slot in app.formats:
        saved = output.format_set.formats.get(slot.id)
        if saved is not None and saved.value in {
            entry.value for entry in slot.values
        }:
            seed[slot.id] = saved
    if output.category is not None and output.category in app.categories:
        seed[_CATEGORY] = CategoryOutput(value=output.category)
    return seed
