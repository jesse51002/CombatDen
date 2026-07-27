// Ports ../../../../../CRM/lib/features/members/data/showcase_defaults.dart.
//
// THE ONE FastApiBackend CALL THIS APP MAKES. Everything else here talks to
// ThemeService; this reads `GET /api/v1/theme/showcase-defaults` — the
// category-keyed demo class + reward cards that fill the phone when there is no
// real gym to draw from, which in this public browser is always.
//
// PUBLIC — no auth. It serves static bundled demo content (no gym or member
// data), which is why an unauthenticated browser may read it at all; see
// ../../../../../FastApiBackend/src/theme/theme_router.py:81 and the wire
// contract in .../src/theme/schema/theme_schema.py (`ShowcaseDefaults` ->
// `{categories: {<Category>: {classes: [...], rewards: [...]}}}`).
//
// It NEVER throws and it is never on the critical path. A failure — offline,
// CORS, 500, a backend that simply is not running — resolves to an EMPTY map,
// the call site falls through to the bundled `showcaseGroupDefaults`, and the
// phone renders fully. The memo is cleared on that failure so a later call
// re-attempts instead of pinning the empty answer for the whole session.
//
// NOTE the dev server's port is pinned to 8080 (../../vite.config.ts) because
// that backend's CORS allowlist contains 8080 but not Vite's default 5173.

import { resolveBackendBaseUrl } from 'theme-react';

import type { ShowcaseClassInfo, ShowcaseReward } from '../showcase/showcaseContent';

/** Matches the Dart client's own cap. */
const TIMEOUT_MS = 15_000;

const PATH = '/api/v1/theme/showcase-defaults';

/** One category's demo class + reward cards, in the showcase's view models. */
export interface ShowcaseGroupContent {
  readonly classes: readonly ShowcaseClassInfo[];
  readonly rewards: readonly ShowcaseReward[];
}

/** The whole category-keyed demo payload, keyed by the wire category string. */
export interface ShowcaseDefaults {
  readonly byCategory: Readonly<Record<string, ShowcaseGroupContent>>;
}

/** What a failed (or not-yet-run) fetch resolves to. */
export const EMPTY_SHOWCASE_DEFAULTS: ShowcaseDefaults = Object.freeze({
  byCategory: Object.freeze({}),
});

/**
 * The demo content for `category`, or `null` when it is absent (or `category`
 * is null) — the caller then falls back to the bundled offline constants.
 * Ports `ShowcaseDefaults.forCategory`.
 */
export function showcaseDefaultsFor(
  defaults: ShowcaseDefaults,
  category: string | null,
): ShowcaseGroupContent | null {
  if (category === null) return null;
  return defaults.byCategory[category] ?? null;
}

// --- Parsing -----------------------------------------------------------------
// Resilient in the same spirit as the library's own `parseThemeConfig`: a
// missing or wrong-typed field degrades to empty rather than failing the
// payload. Every display field on the wire is nullable (the prod columns are).

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function str(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function int(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function parseList<T>(raw: unknown, build: (entry: Record<string, unknown>) => T): readonly T[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(isRecord).map(build);
}

function parseClass(json: Record<string, unknown>): ShowcaseClassInfo {
  return {
    name: str(json['name']),
    imageUrl: str(json['image_url']),
    instructorName: str(json['instructor_name']),
  };
}

function parseReward(json: Record<string, unknown>): ShowcaseReward {
  return {
    title: str(json['title']),
    imageUrl: str(json['image_url']),
    priceLabel: str(json['price_label']),
    pointsCost: int(json['points_cost']),
  };
}

function parseShowcaseDefaults(raw: unknown): ShowcaseDefaults {
  const json = isRecord(raw) ? raw : {};
  const categories = json['categories'];
  if (!isRecord(categories)) return EMPTY_SHOWCASE_DEFAULTS;
  const byCategory: Record<string, ShowcaseGroupContent> = {};
  for (const [key, value] of Object.entries(categories)) {
    if (!isRecord(value)) continue;
    byCategory[key] = {
      classes: parseList(value['classes'], parseClass),
      rewards: parseList(value['rewards'], parseReward),
    };
  }
  return { byCategory };
}

// --- The client + the memo ---------------------------------------------------

/** Throws, so the memoised loader below can decide whether to retry later. */
async function fetchShowcaseDefaults(): Promise<ShowcaseDefaults> {
  const controller = new AbortController();
  const timer = setTimeout(() => {
    controller.abort();
  }, TIMEOUT_MS);
  try {
    const response = await fetch(`${resolveBackendBaseUrl()}${PATH}`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`showcase-defaults fetch failed (${String(response.status)})`);
    }
    return parseShowcaseDefaults(await response.json());
  } finally {
    clearTimeout(timer);
  }
}

/**
 * App-side cache: the demo content is static, so it is fetched once per session
 * and the same promise is shared across every preview re-mount.
 */
let cached: Promise<ShowcaseDefaults> | null = null;

/**
 * The cached demo showcase content. NEVER throws — a failure resolves to
 * `EMPTY_SHOWCASE_DEFAULTS` (so callers use the bundled offline fallback) and
 * clears the memo so a later call re-attempts.
 */
export function loadShowcaseDefaults(): Promise<ShowcaseDefaults> {
  cached ??= fetchShowcaseDefaults().catch((error: unknown) => {
    console.warn('[showcase] defaults fetch failed, using bundled content:', error);
    cached = null; // let the next call re-attempt.
    return EMPTY_SHOWCASE_DEFAULTS;
  });
  return cached;
}

/** Drops the memo. For tests, and for a caller that wants a forced re-read. */
export function resetShowcaseDefaults(): void {
  cached = null;
}
