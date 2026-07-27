// The colour value type + the maths Flutter's `Color` gives for free.
//
// Ports the `dart:ui` Color surface that ../../ThemeFlutter leans on:
// `Color.fromARGB` (see data/models/customization_color.dart),
// `Color.alphaBlend`, and `HSLColor.fromColor(c).lightness`. Flutter hands the
// Dart package a real colour type; the web has only CSS strings, so the runtime
// carries `Rgba` end to end and stringifies at the very edge (a style prop).

/**
 * One resolved sRGB colour. `r`/`g`/`b` are 0–255 integers; `a` is 0–1.
 *
 * DIVERGENCE from ThemeFlutter: Dart quantises alpha to 8 bits
 * (`(alpha * 255).round()` in `ThemeColorValue.parseColorValue`) because
 * `Color.fromARGB` takes an integer channel. CSS takes a float, so the wire's
 * alpha is kept at full precision here. Values round-trip to the same rendered
 * pixel; only the intermediate representation differs.
 */
export interface Rgba {
  readonly r: number;
  readonly g: number;
  readonly b: number;
  readonly a: number;
}

/** Clamps to `[min, max]`, mapping a non-finite input to `min`. */
function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return value < min ? min : value > max ? max : value;
}

/** Builds an `Rgba`, clamping every channel — the ports of `Color.fromARGB`. */
export function rgba(r: number, g: number, b: number, a = 1): Rgba {
  return Object.freeze({
    r: Math.round(clamp(r, 0, 255)),
    g: Math.round(clamp(g, 0, 255)),
    b: Math.round(clamp(b, 0, 255)),
    a: clamp(a, 0, 1),
  });
}

/**
 * CSS for a colour. Always `rgba(...)` — the one notation every browser
 * accepts for both opaque and translucent values, so a caller never has to
 * branch on alpha.
 */
export function toCss(color: Rgba): string {
  return `rgba(${String(color.r)}, ${String(color.g)}, ${String(color.b)}, ${String(color.a)})`;
}

/** The same colour at a different opacity (Flutter's `Color.withValues`). */
export function withAlpha(color: Rgba, alpha: number): Rgba {
  return rgba(color.r, color.g, color.b, alpha);
}

/**
 * Composites `foreground` over `background`, returning the opaque result —
 * Flutter's `Color.alphaBlend`.
 *
 * Needed wherever a translucent token has to become a real colour: the wire's
 * `card` / `second` / `third` derivations all carry alpha, and anything that
 * must reason about the *rendered* colour (a contrast check, a canvas fill)
 * needs it flattened against what sits underneath.
 */
export function alphaBlend(foreground: Rgba, background: Rgba): Rgba {
  const fa = foreground.a;
  if (fa >= 1) return foreground;
  if (fa <= 0) return background;
  const ba = background.a;
  const outA = fa + ba * (1 - fa);
  if (outA <= 0) return rgba(0, 0, 0, 0);
  const mix = (f: number, b: number): number => (f * fa + b * ba * (1 - fa)) / outA;
  return rgba(
    mix(foreground.r, background.r),
    mix(foreground.g, background.g),
    mix(foreground.b, background.b),
    outA,
  );
}

/**
 * HSL lightness, 0–1 — Flutter's `HSLColor.fromColor(c).lightness`. The cheap
 * "is this surface light or dark?" test a call site uses to pick which of two
 * bundled fallbacks to draw on top.
 */
export function hslLightness(color: Rgba): number {
  const r = color.r / 255;
  const g = color.g / 255;
  const b = color.b / 255;
  return (Math.max(r, g, b) + Math.min(r, g, b)) / 2;
}
