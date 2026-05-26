"""LottieRecolorBakeService — bake a recoloured per-tenant animation JSON.

The generative half of resolving a lottie slot. Selection picks a preset
and the recolour LLM maps each region to a palette role; this service takes
that map plus the run's palette and writes a fully-recoloured copy of the
preset's animation into the run dir (``lotties/<slot>.json``) — the way the
icon module copies a matched SVG into ``icons/``. The delivered file already
carries the brand colours, so the app just plays it and never recolours.

The recolour walk is a Python port of the canonical JS implementation in
``LottieHelper/src/main.js`` (``eachColorHandle`` / ``makeSolidHandle`` /
``makeGradientHandles``), differing only in being **scoped to each region's
named layers** instead of recolouring file-wide by hex: every solid
(``ty: fl|st``) and gradient (``ty: gf|gs``) fill/stroke on a region's layers
is set to that region's resolved colour. Only the ``r,g,b`` channels are
written; the artwork's existing alpha / opacity is left untouched.
"""

from __future__ import annotations

import json
from pathlib import Path

from schema.lottie_library import LottiePreset
from schema.output.color_palette import ColorPalette
from schema.primitives import AbsolutePath
from src.core.run_context import RunContext


class LottieRecolorBakeService:
    """Writes the recoloured animation JSON for one resolved lottie slot."""

    async def bake(
        self,
        run_ctx: RunContext,
        *,
        slot_id: str,
        preset: LottiePreset,
        source_json: AbsolutePath,
        region_roles: dict[str, str],
        palette: ColorPalette,
    ) -> AbsolutePath:
        """Recolour ``preset``'s animation with this run's palette and write
        it to ``run_ctx.lottie_path(slot_id)``; return that path.

        ``region_roles`` maps each region name to a palette key; the colour
        for a region is applied to every layer named in that region's
        ``layers``.
        """
        data = json.loads(Path(str(source_json)).read_text(encoding="utf-8"))
        layer_colors = self._layer_colors(preset, region_roles, palette)
        self._recolor_layers(data.get("layers"), layer_colors)
        for asset in data.get("assets") or []:
            if isinstance(asset, dict):
                self._recolor_layers(asset.get("layers"), layer_colors)

        dest = Path(str(run_ctx.lottie_path(slot_id)))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(json.dumps(data), encoding="utf-8")
        return run_ctx.lottie_path(slot_id)

    @staticmethod
    def _layer_colors(
        preset: LottiePreset,
        region_roles: dict[str, str],
        palette: ColorPalette,
    ) -> dict[str, list[float]]:
        """Map each literal layer name to its target ``[r, g, b]`` (0..1
        floats), resolving every region's role through the palette."""
        layer_colors: dict[str, list[float]] = {}
        for region in preset.recolor_regions:
            role = region_roles[region.name]
            rgb = palette.palette[role].rgb
            unit = [rgb.r / 255.0, rgb.g / 255.0, rgb.b / 255.0]
            for layer_name in region.layers:
                layer_colors[layer_name] = unit
        return layer_colors

    @classmethod
    def _recolor_layers(
        cls, layers: object, layer_colors: dict[str, list[float]]
    ) -> None:
        """Recolour every shape on each layer whose ``nm`` is a target."""
        if not isinstance(layers, list):
            return
        for layer in layers:
            if not isinstance(layer, dict):
                continue
            color = layer_colors.get(layer.get("nm"))
            if color is not None:
                cls._recolor_shapes(layer.get("shapes"), color)

    @classmethod
    def _recolor_shapes(cls, shapes: object, color: list[float]) -> None:
        """Walk a shape list (recursing nested group items ``it``) and set
        every solid / gradient fill+stroke colour to ``color``."""
        if not isinstance(shapes, list):
            return
        for shape in shapes:
            if not isinstance(shape, dict):
                continue
            ty = shape.get("ty")
            if ty in ("fl", "st") and isinstance(shape.get("c"), dict):
                cls._set_solid(shape["c"], color)
            elif ty in ("gf", "gs") and isinstance(shape.get("g"), dict):
                cls._set_gradient(shape["g"], color)
            if isinstance(shape.get("it"), list):
                cls._recolor_shapes(shape["it"], color)

    @staticmethod
    def _solid_arrays(c: dict) -> list[list]:
        """Every live ``[r,g,b,...]`` array of a solid colour property: the
        static ``k``, or each keyframe's ``s`` when animated (``a == 1``)."""
        k = c.get("k")
        if c.get("a") == 1 and isinstance(k, list):
            return [kf["s"] for kf in k if isinstance(kf, dict) and isinstance(kf.get("s"), list)]
        return [k] if isinstance(k, list) else []

    @classmethod
    def _set_solid(cls, c: dict, color: list[float]) -> None:
        """Set the r,g,b of every array of a solid colour (alpha untouched)."""
        for arr in cls._solid_arrays(c):
            if len(arr) >= 3:
                arr[0], arr[1], arr[2] = color

    @staticmethod
    def _set_gradient(g: dict, color: list[float]) -> None:
        """Set the r,g,b of every colour stop of a gradient. Stops live in a
        flat array ``g.k.k = [pos,r,g,b, …]`` (static, or per keyframe ``s``
        when animated); ``g.p`` is the colour-stop count. Opacity stops that
        follow the colour stops are left untouched."""
        prop = g.get("k")
        if not isinstance(prop, dict):
            return
        k = prop.get("k")
        if prop.get("a") == 1 and isinstance(k, list):
            arrays = [kf["s"] for kf in k if isinstance(kf, dict) and isinstance(kf.get("s"), list)]
        else:
            arrays = [k] if isinstance(k, list) else []
        stops = g.get("p") or 0
        for arr in arrays:
            for i in range(stops):
                base = i * 4  # [pos, r, g, b] per stop
                if len(arr) >= base + 4:
                    arr[base + 1], arr[base + 2], arr[base + 3] = color
