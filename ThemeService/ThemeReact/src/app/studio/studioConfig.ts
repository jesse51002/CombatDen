// Where the GENERATION STUDIO lives.
//
// The studio is a THIRD backend, and it is deliberately not in
// `../../lib/config.ts` alongside the other two. That module belongs to the
// published library — `src/lib/` is the app-agnostic runtime a consumer
// installs, and the studio is a local-only laptop tool that starts paid
// pipeline runs (`ThemeService/src/studio/`, bound to 127.0.0.1:8002 and never
// deployed). Teaching the shipped runtime about it would put a base URL in the
// bundle for a server no consumer can reach.
//
// So this file mirrors that module's LADDER rather than importing it: explicit
// override → Vite env var → default. Same three steps, same empty-string rule,
// same trailing-slash normalisation — see `src/lib/config.ts`, which is the
// pattern of record.

/**
 * `ThemeService/Makefile`'s `studio` target:
 * `uvicorn src.studio.main:app --host 127.0.0.1 --port 8002`.
 *
 * 127.0.0.1 rather than `localhost` on purpose. The studio binds the loopback
 * ADDRESS, and its own CORS allowlist (`src/studio/config.py`) names both
 * `http://localhost:8080` and `http://127.0.0.1:8080` because those are two
 * different browser origins — this file resolves the other half of that pair.
 */
const DEFAULT_STUDIO_BASE_URL = 'http://127.0.0.1:8002';

/** Trailing slashes make every joined path double-slashed. Strip them once. */
function normalise(url: string): string {
  return url.replace(/\/+$/, '');
}

/**
 * Reads a Vite env var when one is present, tolerating every environment where
 * `import.meta.env` does not exist (a test runner, SSR).
 */
function viteEnv(key: string): string | undefined {
  const env = (import.meta as ImportMeta & { env?: Record<string, string | undefined> }).env;
  const value = env?.[key];
  return value !== undefined && value !== '' ? value : undefined;
}

/**
 * An EMPTY override means "not configured", not "use an empty base URL" — `??`
 * alone would pass `''` through and turn every request into a relative path
 * against whatever origin is serving the page.
 */
function present(value: string | undefined): string | undefined {
  return value !== undefined && value !== '' ? value : undefined;
}

/** The studio's base URL. Local: `cd ThemeService && make studio`. */
export function resolveStudioBaseUrl(override?: string): string {
  return normalise(
    present(override) ?? viteEnv('VITE_STUDIO_BASE_URL') ?? DEFAULT_STUDIO_BASE_URL,
  );
}

/** The default, exported so an error message can name the port it expected. */
export const DEFAULT_STUDIO_URL = DEFAULT_STUDIO_BASE_URL;
