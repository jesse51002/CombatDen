// One slot's full font record — `font_set.fonts[slot]` on the wire.
//
// NO DART COUNTERPART, and the absence is the point. ThemeFlutter's
// `ThemeConfig` reads only the flat `fonts` map (slot -> family) because
// `GoogleFonts.getFont` needs nothing else, so the API collapsed the record to
// that one field and threw the rest away. It no longer does: a run writes the
// family's Google Fonts category, its own name for the face, and a paragraph on
// what the face is for. The flat map stays exactly as it was — this is the
// record beside it, and if the Flutter side ever wants it, this is the port of
// record rather than a second reading of the same wire.

import { isRecord, stringField } from './json';

/** The run's reasoning about one font slot, as opposed to just its family. */
export interface ThemeFontFace {
  /** The Google Fonts family — the same string the flat `fonts` map carries. */
  readonly family: string;
  /**
   * Google's own classification for the family (`sans-serif`, `serif`,
   * `display`, `handwriting`, `monospace`). The pipeline reads it off the
   * catalog after validating the pick, so it cannot drift from what Google
   * actually serves.
   *
   * Deliberately a plain `string` rather than a union: this runtime is a live
   * override for values a server produces, so a category Google adds tomorrow
   * should reach the surface that displays it instead of being narrowed away
   * here. Same reason `imageComplexity` is a string.
   */
  readonly category: string;
  /** The run's own name for the face, e.g. "Athletic Modern". */
  readonly displayName: string;
  /** The run's written reasoning for picking it — prose, at paragraph length. */
  readonly description: string;
}

/**
 * One `font_set.fonts[slot]` entry, or `null` when it carries no family.
 *
 * Dropping a family-less record keeps "absent" and "present but blank" a single
 * case for every reader, exactly as `parseStringMap` drops an empty URL.
 */
export function parseThemeFontFace(raw: unknown): ThemeFontFace | null {
  const json = isRecord(raw) ? raw : {};
  const family = stringField(json['family']);
  if (family === '') return null;
  return {
    family,
    category: stringField(json['category']),
    displayName: stringField(json['display_name']),
    description: stringField(json['description']),
  };
}
