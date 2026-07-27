// Ports ../../ThemeFlutter/lib/data/models/customization.dart.

import type { Rgba } from '../theme/color';

import type { ColorMode } from './colorMode';
import { parseColorMode } from './colorMode';
import { isRecord, parseSlotMap, parseStringMap, stringField } from './json';
import type { ThemeColorValue } from './themeColorValue';
import { parseColorValue, parseThemeColorValue } from './themeColorValue';

/**
 * A loaded, resolved theme. App-agnostic: colours, images, fonts, texts and
 * icons are typed-value maps keyed by slot id — the runtime never knows which
 * slots a given app expects (that is the caller's `expected*` lists).
 *
 * Parsing is resilient: a missing/non-object section is `{}` and a single
 * malformed slot is skipped, never failing the whole payload.
 */
export interface ThemeConfig {
  readonly app: string;
  /** The app/brand name (e.g. "CombatDen"). Stable across the app's designs. */
  readonly displayName: string;
  /** This run's design/style name (e.g. "Apex MMA") — what a picker labels it. */
  readonly designName: string;
  readonly colorMode: ColorMode;
  readonly colors: Readonly<Record<string, ThemeColorValue>>;
  /**
   * The wire's flat recommendation palette: every `<slot>_<derivation>` pair
   * (e.g. `primary_dark`, `accent_popup`) plus the shared surface tokens
   * (`card`, `popup`, `divider`) and the base roles (`primary`, `background`,
   * `text`, `accent`).
   */
  readonly palette: Readonly<Record<string, Rgba>>;
  /** Slot -> image fetch URL. Flat on the wire (no wrapper, no prompt). */
  readonly images: Readonly<Record<string, string>>;
  /** Slot -> Google Fonts family. Flat on the wire. */
  readonly fonts: Readonly<Record<string, string>>;
  /** Slot -> brand-rewritten copy (e.g. `class_booked_headline` → "You're in."). */
  readonly texts: Readonly<Record<string, string>>;
  /** Slot -> SVG fetch URL. Flat on the wire, exactly like `images`. */
  readonly icons: Readonly<Record<string, string>>;
}

/**
 * Builds a `ThemeConfig` from the `GET /apps/{appId}/{designId}` envelope:
 * `color_set.{mode, colors, palette}` and `text_set.texts` (typed, passthrough
 * from `output.yaml`), plus flat `images` / `fonts` / `icons` maps at the top
 * level. Every missing section degrades to empty — this never throws.
 */
export function parseThemeConfig(raw: unknown): ThemeConfig {
  const json = isRecord(raw) ? raw : {};
  const colorSet = json['color_set'];
  const textSet = json['text_set'];
  return {
    app: stringField(json['app']),
    displayName: stringField(json['display_name']),
    designName: stringField(json['design_name']),
    colorMode: parseColorMode(isRecord(colorSet) ? colorSet['mode'] : null),
    colors: parseSlotMap(isRecord(colorSet) ? colorSet['colors'] : null, parseThemeColorValue),
    palette: parsePalette(isRecord(colorSet) ? colorSet['palette'] : null),
    images: parseStringMap(json['images']),
    fonts: parseStringMap(json['fonts']),
    texts: parseTexts(isRecord(textSet) ? textSet['texts'] : null),
    icons: parseStringMap(json['icons']),
  };
}

/**
 * The flat `color_set.palette` block: bare `ColorValue`s, so a `rgb` block is
 * all there is to read. Ports `_parsePalette`.
 */
function parsePalette(raw: unknown): Record<string, Rgba> {
  const result: Record<string, Rgba> = {};
  if (!isRecord(raw)) return result;
  for (const [key, value] of Object.entries(raw)) {
    const color = parseColorValue(value);
    if (color !== null) result[key] = color;
  }
  return result;
}

/**
 * `text_set.texts` is `slot -> {value}`, not `slot -> string` — the one section
 * whose leaf needs unwrapping. Empty values are dropped so an empty override
 * falls back like an absent one. Ports `_parseTexts`.
 */
function parseTexts(raw: unknown): Record<string, string> {
  return parseSlotMap(raw, (entry) => {
    const value = entry['value'];
    return typeof value === 'string' && value !== '' ? value : null;
  });
}
