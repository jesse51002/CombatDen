// The disk last-good + sticky selection, ported from the `SharedPreferences`
// half of ../../ThemeFlutter/lib/customization_service.dart.
//
// The two keys are VERBATIM the Dart ones. They are the contract between this
// runtime and any other client storing the same theme on the same origin —
// renaming one silently orphans every returning visitor's last-good copy and
// their sticky pick, which surfaces as "the theme flashes back to the seed
// design on every reload" rather than as an error.

/** The last-good theme payload, stored as the RAW wire JSON. */
export const LAST_GOOD_KEY = 'customization_last_good_json';

/** The design the user picked on a previous visit. */
export const SELECTED_DESIGN_KEY = 'customization_selected_design_id';

/**
 * `localStorage` when it exists and is usable, else `null`.
 *
 * It can be absent (SSR, a worker) or present-but-throwing (Safari private
 * browsing, a blocked third-party context). Every access below goes through
 * here and swallows, because losing the cache is a degraded experience while
 * throwing would take down `initialize()` — and `initialize()` never throws.
 *
 * `window.localStorage` is preferred over the bare global on purpose: Node 22+
 * ships its OWN experimental `globalThis.localStorage`, which is `undefined`
 * unless the process was started with `--localstorage-file`, and it SHADOWS the
 * jsdom one under the test runner. Reading through `window` gets the real store
 * in a browser and in jsdom, and correctly gets nothing under SSR.
 */
function storage(): Storage | null {
  try {
    if (typeof window !== 'undefined') return window.localStorage;
    return typeof localStorage === 'undefined' ? null : localStorage;
  } catch {
    return null;
  }
}

function read(key: string): string | null {
  try {
    return storage()?.getItem(key) ?? null;
  } catch {
    return null;
  }
}

function write(key: string, value: string): void {
  try {
    storage()?.setItem(key, value);
  } catch {
    // Quota exceeded / private mode. The theme still works this session.
  }
}

/** The raw last-good wire JSON from a previous visit, if any. */
export function readLastGood(): string | null {
  return read(LAST_GOOD_KEY);
}

/** Persists the raw wire JSON that was just adopted. */
export function writeLastGood(rawJson: string): void {
  write(LAST_GOOD_KEY, rawJson);
}

/** The design the user last picked, if any. */
export function readSelectedDesignId(): string | null {
  const value = read(SELECTED_DESIGN_KEY);
  return value !== null && value !== '' ? value : null;
}

/** Makes a `selectDesign` stick across reloads. */
export function writeSelectedDesignId(designId: string): void {
  write(SELECTED_DESIGN_KEY, designId);
}
