// Ports ../../ThemeFlutter/lib/data/models/customization_color.dart.

import type { Rgba } from '../theme/color';
import { rgba } from '../theme/color';

import { isRecord, stringField } from './json';

/**
 * One resolved brand colour. App-agnostic leaf type.
 *
 * The service ships every colour in four formats (oklch / hsl / rgb / hex).
 * This reads `rgb` and ONLY `rgb` — the service has already done the OKLCH→sRGB
 * conversion, so re-deriving it client-side would be a second, divergent
 * implementation of the same maths.
 */
export interface ThemeColorValue {
  /** Parsed sRGB colour, or `null` when the `rgb` block was missing/unparseable. */
  readonly color: Rgba | null;
  /**
   * The seven pre-computed variants keyed by derivation id (`second`, `third`,
   * `card`, `popup`, `dark`, `light`, `regular_text`). A derivation whose `rgb`
   * block was unparseable is absent rather than null.
   */
  readonly derivations: Readonly<Record<string, Rgba>>;
  /** Human label, e.g. "Red Corner". */
  readonly displayName: string;
  /** Purpose/usage prose for the colour. */
  readonly description: string;
}

/**
 * Parses a `ColorValue` wire object (`{oklch, hsl, rgb, hex}`) into an `Rgba`
 * by reading its `rgb` block; `null` on any malformed input.
 *
 * Exported because the root parser reuses it for the flat `color_set.palette`
 * block, whose entries are bare `ColorValue`s rather than full `ColorOutput`s.
 *
 * `alpha` is nullable on the wire (it is literally `alpha: null` for every
 * opaque colour in a real `output.yaml`) and means "fully opaque".
 */
export function parseColorValue(raw: unknown): Rgba | null {
  if (!isRecord(raw)) return null;
  const rgb = raw['rgb'];
  if (!isRecord(rgb)) return null;
  const r = rgb['r'];
  const g = rgb['g'];
  const b = rgb['b'];
  if (!isFiniteNumber(r) || !isFiniteNumber(g) || !isFiniteNumber(b)) return null;
  const alpha = rgb['alpha'];
  return rgba(r, g, b, isFiniteNumber(alpha) ? alpha : 1);
}

export function parseThemeColorValue(raw: unknown): ThemeColorValue {
  const json = isRecord(raw) ? raw : {};
  return {
    color: parseColorValue(json['color']),
    derivations: parseDerivations(json['derivations']),
    displayName: stringField(json['display_name']),
    description: stringField(json['description']),
  };
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function parseDerivations(raw: unknown): Record<string, Rgba> {
  const result: Record<string, Rgba> = {};
  if (!isRecord(raw)) return result;
  for (const [key, value] of Object.entries(raw)) {
    const color = parseColorValue(value);
    if (color !== null) result[key] = color;
  }
  return result;
}
