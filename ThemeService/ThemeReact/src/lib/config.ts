// Where the two backends live.
//
// The Flutter package resolves its base URL from a compile-time dart-define
// (`String.fromEnvironment('CUST_BASE_URL', defaultValue: 'http://localhost:8001')`
// — see ../../ThemeFlutter/lib/data/customization_api_client.dart). The web
// equivalent is a Vite env var, with the same localhost default so the dev
// loop needs no configuration.
//
// Read at call time rather than captured at module load, so a UMD consumer can
// pass explicit values through ThemeRuntime.initialize instead.

/** ThemeService's read API. Local: `cd ThemeService && make api`. */
const DEFAULT_THEME_BASE_URL = 'http://localhost:8001';

/**
 * FastApiBackend, for the one public read this app makes
 * (`GET /api/v1/theme/showcase-defaults`).
 *
 * NOTE the port this app's dev server runs on is pinned to 8080 because that
 * backend's CORS allowlist contains 8080 but not Vite's default 5173. See
 * vite.config.ts.
 */
const DEFAULT_BACKEND_BASE_URL = 'http://localhost:8000';

export const DEFAULTS = {
  themeBaseUrl: DEFAULT_THEME_BASE_URL,
  backendBaseUrl: DEFAULT_BACKEND_BASE_URL,
} as const;

/** Explicit base-URL overrides, for consumers without a Vite build. */
export interface ThemeReactConfig {
  themeBaseUrl?: string;
  backendBaseUrl?: string;
}

/**
 * Reads a Vite env var when one is present, tolerating every environment where
 * `import.meta.env` does not exist (the UMD bundle, a test runner, SSR).
 */
function viteEnv(key: string): string | undefined {
  const env = (import.meta as ImportMeta & { env?: Record<string, string | undefined> }).env;
  const value = env?.[key];
  return value !== undefined && value !== '' ? value : undefined;
}

/** Trailing slashes make every joined path double-slashed. Strip them once. */
function normalise(url: string): string {
  return url.replace(/\/+$/, '');
}

/**
 * An EMPTY override means "not configured", not "use an empty base URL" —
 * `??` alone would pass `''` straight through and turn every request into a
 * relative path against whatever origin happens to be serving the page.
 */
function present(value: string | undefined): string | undefined {
  return value !== undefined && value !== '' ? value : undefined;
}

export function resolveThemeBaseUrl(override?: string): string {
  return normalise(
    present(override) ?? viteEnv('VITE_THEME_BASE_URL') ?? DEFAULT_THEME_BASE_URL,
  );
}

export function resolveBackendBaseUrl(override?: string): string {
  return normalise(
    present(override) ?? viteEnv('VITE_BACKEND_BASE_URL') ?? DEFAULT_BACKEND_BASE_URL,
  );
}
