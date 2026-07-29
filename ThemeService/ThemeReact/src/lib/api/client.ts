// Ports ../../ThemeFlutter/lib/data/customization_api_client.dart.

import { resolveThemeBaseUrl } from '../config';
import type { ThemeStylesPage } from '../models/themeStylesPage';
import { parseThemeStylesPage } from '../models/themeStylesPage';

/**
 * Thrown on any theme fetch failure; the store catches it and degrades to the
 * localStorage last-good copy, then to defaults. Ports `ThemeFetchException`.
 */
export class ThemeFetchError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ThemeFetchError';
  }
}

/**
 * Hard cap on any single request. Dart sets this as Dio's connect/receive
 * timeout AND again as an outer `.timeout(5s)` on the awaited future; `fetch`
 * has no built-in timeout, so an `AbortController` is the equivalent — and it
 * genuinely cancels the request rather than just abandoning the promise.
 *
 * The point is that app startup can never hang on the theme service.
 */
const REQUEST_TIMEOUT_MS = 5000;

export interface ThemeStylesPageQuery {
  offset?: number;
  limit?: number;
  /** Case-insensitive substring match on id or display name. */
  query?: string | null;
}

/**
 * Dedicated read-only client for the public ThemeService. App-agnostic,
 * unauthenticated, short timeouts so app startup never hangs on it.
 *
 * The request paths are package-internal — the caller only supplies which
 * app/design to load, and (optionally) a base URL for a non-default deployment.
 */
export class ThemeApiClient {
  readonly appId: string;
  readonly designId: string;
  /** Resolved base URL, also used to absolutise relative asset URLs. */
  readonly baseUrl: string;

  constructor(appId: string, designId: string, baseUrl?: string) {
    this.appId = appId;
    this.designId = designId;
    this.baseUrl = resolveThemeBaseUrl(baseUrl);
  }

  /**
   * `GET /apps/{appId}/{designId}` — the resolved theme, raw. Returns the JSON
   * object untouched so the store can persist the EXACT bytes it adopted (the
   * localStorage last-good copy is re-parsed on the next boot, so it has to be
   * the wire shape, not a re-serialised model).
   */
  fetchOutput = async (designId?: string): Promise<unknown> => {
    const path = `/apps/${encodeURIComponent(this.appId)}/${encodeURIComponent(
      designId ?? this.designId,
    )}`;
    const data = await this.getJson(path, 'Theme fetch failed');
    if (!isObject(data)) {
      throw new ThemeFetchError('Theme response was not a JSON object');
    }
    return data;
  };

  /**
   * `GET /apps/{appId}/styles` — one page of the app's selectable styles, with
   * the post-filter total so callers can detect end-of-list. Same
   * degrade-on-failure contract as `fetchOutput`.
   */
  fetchStylesPage = async ({
    offset = 0,
    limit = 20,
    query = null,
  }: ThemeStylesPageQuery = {}): Promise<ThemeStylesPage> => {
    const params = new URLSearchParams({ offset: String(offset), limit: String(limit) });
    if (query !== null && query !== '') params.set('q', query);
    const path = `/apps/${encodeURIComponent(this.appId)}/styles?${params.toString()}`;
    const data = await this.getJson(path, 'Styles fetch failed');
    if (!isObject(data)) {
      throw new ThemeFetchError('Styles response was not a JSON object');
    }
    return parseThemeStylesPage(data, this.resolveImageUrl);
  };

  /**
   * Absolutises a possibly-relative asset URL. Already-absolute URLs pass
   * through untouched, which is the normal case in production: ThemeService
   * defaults `ASSETS_CDN_BASE_URL` to the prod CDN, so every image and icon
   * arrives as an absolute `cdn.combatden.net` link.
   */
  resolveImageUrl = (raw: string): string => {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    const path = raw.startsWith('/') ? raw : `/${raw}`;
    return `${this.baseUrl}${path}`;
  };

  private getJson = async (path: string, failureLabel: string): Promise<unknown> => {
    const controller = new AbortController();
    const timer = setTimeout(() => {
      controller.abort();
    }, REQUEST_TIMEOUT_MS);
    try {
      const response = await fetch(`${this.baseUrl}${path}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new ThemeFetchError(`${failureLabel}: HTTP ${String(response.status)}`);
      }
      return await response.json();
    } catch (error) {
      if (error instanceof ThemeFetchError) throw error;
      throw new ThemeFetchError(`${failureLabel}: ${describe(error)}`);
    } finally {
      clearTimeout(timer);
    }
  };
}

function isObject(value: unknown): boolean {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function describe(error: unknown): string {
  if (error instanceof Error) {
    return error.name === 'AbortError'
      ? `timed out after ${String(REQUEST_TIMEOUT_MS)}ms`
      : error.message;
  }
  return String(error);
}
