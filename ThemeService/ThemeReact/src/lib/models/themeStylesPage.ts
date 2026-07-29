// Ports ../../ThemeFlutter/lib/data/models/customization_styles_page.dart.

import { intField, isRecord } from './json';
import type { ThemeStyle } from './themeStyle';
import { parseThemeStyle } from './themeStyle';

/**
 * One page of the paginated `GET /apps/{appId}/styles` envelope.
 *
 * `items` is the slice; `total` is the POST-FILTER match count (the full list
 * size for the active search query, not the catalog size); `offset` and `limit`
 * echo the request, so a caller can derive `hasMore` without tracking what it
 * asked for.
 */
export interface ThemeStylesPage {
  readonly items: readonly ThemeStyle[];
  readonly total: number;
  readonly offset: number;
  readonly limit: number;
}

/** Empty page — the initial state before the first fetch resolves. */
export const EMPTY_STYLES_PAGE: ThemeStylesPage = Object.freeze({
  items: Object.freeze([]) as readonly ThemeStyle[],
  total: 0,
  offset: 0,
  limit: 0,
});

/** True when the next page would yield at least one more item. */
export function hasMoreStyles(page: ThemeStylesPage): boolean {
  return page.offset + page.items.length < page.total;
}

/**
 * Builds from the wire envelope. Resilient like `parseThemeStyle`: missing or
 * wrong-typed numerics degrade to 0, a missing `items` becomes an empty list,
 * and an item with no `id` is dropped (it could never be selected).
 */
export function parseThemeStylesPage(
  raw: unknown,
  resolveUrl: (rawUrl: string) => string,
): ThemeStylesPage {
  const json = isRecord(raw) ? raw : {};
  const rawItems = json['items'];
  const items = Array.isArray(rawItems)
    ? rawItems
        .filter(isRecord)
        .map((item) => parseThemeStyle(item, resolveUrl))
        .filter((style) => style.id !== '')
    : [];
  return {
    items,
    total: intField(json['total']),
    offset: intField(json['offset']),
    limit: intField(json['limit']),
  };
}
