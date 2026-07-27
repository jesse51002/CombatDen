// The lossy-tolerant primitives every model parser in here is built from.
//
// Ports the private helpers on ThemeConfig in
// ../../ThemeFlutter/lib/data/models/customization.dart (`_parseMap`,
// `_parseStringMap`, `_parsePalette`, `_parseTexts`) — Dart gets `is Map` /
// `is String` checks for free from its type system; TypeScript's types are
// erased at runtime, so the same narrowing has to be written out.
//
// The contract these encode: a missing or wrong-typed SECTION is `{}`, and a
// single malformed SLOT is skipped rather than failing the whole payload.

/** A JSON object. The only shape any of these parsers descends into. */
export type JsonRecord = Record<string, unknown>;

/** True for a plain JSON object — not null, not an array. */
export function isRecord(raw: unknown): raw is JsonRecord {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw);
}

/** A string field, or `''` when absent/wrong-typed. Ports `as String? ?? ''`. */
export function stringField(raw: unknown): string {
  return typeof raw === 'string' ? raw : '';
}

/** An int field, or `0`. Ports `ThemeStylesPage.fromJson`'s local `asInt`. */
export function intField(raw: unknown): number {
  return typeof raw === 'number' && Number.isFinite(raw) ? Math.trunc(raw) : 0;
}

/**
 * `raw` as a slot map, running `parse` per entry. Non-object entries are
 * skipped, a `parse` that throws costs only its own slot, and a `parse`
 * returning `null` drops the slot. Ports `_parseMap` / `_parsePalette`.
 */
export function parseSlotMap<T>(
  raw: unknown,
  parse: (value: JsonRecord) => T | null,
): Record<string, T> {
  const result: Record<string, T> = {};
  if (!isRecord(raw)) return result;
  for (const [key, value] of Object.entries(raw)) {
    if (!isRecord(value)) continue;
    try {
      const parsed = parse(value);
      if (parsed !== null) result[key] = parsed;
    } catch {
      // Skip a malformed slot; keep the rest.
    }
  }
  return result;
}

/**
 * `raw` as a flat `slot -> non-empty string` map. Wrong-typed and EMPTY values
 * are dropped, which is what lets every resolver treat "absent" and "present
 * but blank" identically. Ports `_parseStringMap`.
 */
export function parseStringMap(raw: unknown): Record<string, string> {
  const result: Record<string, string> = {};
  if (!isRecord(raw)) return result;
  for (const [key, value] of Object.entries(raw)) {
    if (typeof value !== 'string' || value === '') continue;
    result[key] = value;
  }
  return result;
}
