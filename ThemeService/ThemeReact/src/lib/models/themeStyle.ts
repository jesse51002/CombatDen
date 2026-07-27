// Ports ../../ThemeFlutter/lib/data/models/customization_style.dart.

import { isRecord, stringField } from './json';

/**
 * One selectable style from `GET /apps/{appId}/styles`. App-agnostic: the run
 * `id` to switch to, the human `displayName` to show, an absolute
 * `celebrationImageUrl` for the card art, and the `category` bucket (the
 * app-declared vocabulary — `Fighting`, `Yoga`, `Pilates`, … for CombatDen)
 * a picker filters on.
 *
 * DIVERGENCE from ThemeFlutter: no `gymId`. The Dart model carries one for a
 * different catalog (AppManagement's VideoService gym browser); ThemeService's
 * own wire — `../src/api/schema/style_summary.py`, `extra="forbid"` — is
 * exactly `{id, display_name, celebration_image, category}` and never ships it.
 *
 * Parsing is resilient, mirroring `parseThemeConfig`: missing fields degrade to
 * empty strings / null rather than throwing.
 */
export interface ThemeStyle {
  readonly id: string;
  readonly displayName: string;
  readonly celebrationImageUrl: string;
  readonly category: string | null;
}

/**
 * Builds one style from a wire item. `resolveUrl` absolutises the relative
 * `celebration_image` path the API ships when no CDN is configured (the same
 * convention as the image slots in `ThemeConfig`).
 */
export function parseThemeStyle(
  raw: unknown,
  resolveUrl: (rawUrl: string) => string,
): ThemeStyle {
  const json = isRecord(raw) ? raw : {};
  const image = stringField(json['celebration_image']);
  const category = json['category'];
  return {
    id: stringField(json['id']),
    displayName: stringField(json['display_name']),
    celebrationImageUrl: image === '' ? '' : resolveUrl(image),
    category: typeof category === 'string' ? category : null,
  };
}
