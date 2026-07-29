// Ports ../../ThemeFlutter/lib/data/models/customization.dart.

import type { Rgba } from '../theme/color';

import type { ColorMode } from './colorMode';
import { parseColorMode } from './colorMode';
import { isRecord, parseSlotMap, parseStringMap, stringField } from './json';
import type { ThemeColorValue } from './themeColorValue';
import { parseColorValue, parseThemeColorValue } from './themeColorValue';
import type { ThemeFontFace } from './themeFontFace';
import { parseThemeFontFace } from './themeFontFace';

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
  /**
   * The run's own classification bucket (e.g. "Fighting") — the value the
   * styles list filters on, a bare run-wide string rather than a slot.
   * `''` for a theme produced before the pipeline classified its runs.
   */
  readonly category: string;
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
  /**
   * Slot -> the visual-complexity tier the run assigned that image's prompt
   * (`low` / `medium` / `high`), which is what picked the generator's quality
   * setting. From the wire's `image_set` group, because the flat `images` map
   * is frozen at `slot -> string` for the deployed Dart client.
   *
   * A plain `string`, not a union, for the reason on `ThemeFontFace.category`:
   * a tier this build has never heard of should still reach a surface that
   * prints it.
   */
  readonly imageComplexity: Readonly<Record<string, string>>;
  /** Slot -> Google Fonts family. Flat on the wire. */
  readonly fonts: Readonly<Record<string, string>>;
  /**
   * Slot -> the full font record (family, Google Fonts category, the run's own
   * name for the face, and its written reasoning). From the wire's `font_set`
   * group, beside the flat `fonts` map rather than instead of it.
   *
   * Read `fonts` for the family and treat everything here as detail that may be
   * absent: a last-good copy stored before the API carried `font_set` parses to
   * `{}` here while `fonts` still resolves every slot.
   */
  readonly fontFaces: Readonly<Record<string, ThemeFontFace>>;
  /** Slot -> brand-rewritten copy (e.g. `class_booked_headline` → "You're in."). */
  readonly texts: Readonly<Record<string, string>>;
  /** Slot -> SVG fetch URL. Flat on the wire, exactly like `images`. */
  readonly icons: Readonly<Record<string, string>>;
  /**
   * Slot -> the ARRANGEMENT the run chose for that surface (e.g.
   * `home_format` → `timeSpine`). Each value is the name of an enum value in
   * the client's own layout vocabulary, so a consumer parses it back to its
   * enum and falls back to the arrangement it ships when the name is unknown.
   *
   * A plain `string`, not a union, for the same reason as
   * `ThemeFontFace.category`: this runtime must not need rebuilding when the
   * vocabulary gains a value, and a surface that merely PRINTS the pick should
   * print one it has never heard of rather than dropping it.
   *
   * Empty for a theme produced before the pipeline chose arrangements, and for
   * an app that declares no format slots.
   */
  readonly formats: Readonly<Record<string, string>>;
}

/**
 * Builds a `ThemeConfig` from the `GET /apps/{appId}/{designId}` envelope:
 * `color_set.{mode, colors, palette}`, `font_set.fonts`, `image_set.images` and
 * `text_set.texts` (typed, passthrough or lightly projected from
 * `output.yaml`), plus flat `images` / `fonts` / `icons` maps at the top level
 * and the run-wide `category`. Every missing section degrades to empty — this
 * never throws, which is what lets a last-good copy stored by an older build
 * (no `category`, no `font_set`, no `image_set`) keep loading.
 */
export function parseThemeConfig(raw: unknown): ThemeConfig {
  const json = isRecord(raw) ? raw : {};
  const colorSet = json['color_set'];
  const fontSet = json['font_set'];
  const imageSet = json['image_set'];
  const textSet = json['text_set'];
  const formatSet = json['format_set'];
  return {
    app: stringField(json['app']),
    displayName: stringField(json['display_name']),
    designName: stringField(json['design_name']),
    category: stringField(json['category']),
    colorMode: parseColorMode(isRecord(colorSet) ? colorSet['mode'] : null),
    colors: parseSlotMap(isRecord(colorSet) ? colorSet['colors'] : null, parseThemeColorValue),
    palette: parsePalette(isRecord(colorSet) ? colorSet['palette'] : null),
    images: parseStringMap(json['images']),
    imageComplexity: parseComplexity(isRecord(imageSet) ? imageSet['images'] : null),
    fonts: parseStringMap(json['fonts']),
    fontFaces: parseSlotMap(
      isRecord(fontSet) ? fontSet['fonts'] : null,
      parseThemeFontFace,
    ),
    texts: parseValued(isRecord(textSet) ? textSet['texts'] : null),
    icons: parseStringMap(json['icons']),
    formats: parseValued(isRecord(formatSet) ? formatSet['formats'] : null),
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
 * `image_set.images` is `slot -> {url, complexity}`. Only the tier is read here:
 * the URL half is the flat `images` map, already parsed above, and reading it
 * twice would invite the two copies to disagree in a consumer's head.
 */
function parseComplexity(raw: unknown): Record<string, string> {
  return parseSlotMap(raw, (entry) => {
    const value = entry['complexity'];
    return typeof value === 'string' && value !== '' ? value : null;
  });
}

/**
 * The two sections whose leaf is `slot -> {value}` rather than `slot -> string`
 * — `text_set.texts` and `format_set.formats`. Empty values are dropped so an
 * empty override falls back exactly like an absent one, which for a format
 * means the client renders the arrangement it ships. Generalises `_parseTexts`,
 * whose Dart counterpart predates the format group.
 */
function parseValued(raw: unknown): Record<string, string> {
  return parseSlotMap(raw, (entry) => {
    const value = entry['value'];
    return typeof value === 'string' && value !== '' ? value : null;
  });
}
