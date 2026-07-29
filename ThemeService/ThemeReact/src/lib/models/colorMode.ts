// Ports ../../ThemeFlutter/lib/data/models/color_mode.dart.

/**
 * Light/dark target a resolved palette was generated for. Mirrors
 * ThemeService's `schema/color_mode.py` (serialises `"light"` / `"dark"`).
 */
export type ColorMode = 'light' | 'dark';

/**
 * Defaults to `dark`: the bundled const-fallback palette is the dark CombatDen
 * one, so an absent/unknown mode (an old localStorage copy, a malformed
 * payload) stays consistent with the canvas actually rendered when the theme is
 * unavailable.
 */
export function parseColorMode(raw: unknown): ColorMode {
  return typeof raw === 'string' && raw.toLowerCase() === 'light' ? 'light' : 'dark';
}

export function isLightMode(mode: ColorMode): boolean {
  return mode === 'light';
}

export function isDarkMode(mode: ColorMode): boolean {
  return mode === 'dark';
}
