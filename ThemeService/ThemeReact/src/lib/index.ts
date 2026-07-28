// theme-react — the public entry, and the ONLY export surface.
//
// This package is the React mirror of ../../ThemeFlutter (the `theme_flutter`
// Dart package): the white-label theme runtime. It fetches a tenant's resolved
// branding from the ThemeService API, keeps a last-good copy in localStorage,
// and exposes resolvers that never throw.
//
// It ships NO screens and NO bundled assets, exactly as ThemeFlutter doesn't —
// the showcase preview screens live in the consuming app (src/app/).
//
// The layout below mirrors the Dart package one-to-one:
//   runtime.ts        ← customization_runtime.dart
//   store/            ← customization_service.dart, service_locator.dart
//   api/              ← data/customization_api_client.dart
//   models/           ← data/models/*.dart
//   theme/            ← theme/*.dart
//   react/            ← (no counterpart: Flutter uses ListenableBuilder)
//   motion/           ← theme/animation/*.dart

// --- Bootstrap ---------------------------------------------------------------
export {
  ThemeRuntime,
  initializeTheme,
  resetThemeRuntime,
  themeIsReady,
  activeDesignId,
  selectDesign,
  fetchStylesPage,
  resolveImageUrl,
} from './runtime';
export type { InitializeThemeOptions } from './runtime';

// --- Configuration -----------------------------------------------------------
export { resolveThemeBaseUrl, resolveBackendBaseUrl, DEFAULTS } from './config';
export type { ThemeReactConfig } from './config';

// --- API client --------------------------------------------------------------
export { ThemeApiClient, ThemeFetchError } from './api/client';
export type { ThemeStylesPageQuery } from './api/client';

// --- Models ------------------------------------------------------------------
export { parseColorMode, isLightMode, isDarkMode } from './models/colorMode';
export type { ColorMode } from './models/colorMode';
export { parseThemeConfig } from './models/themeConfig';
export type { ThemeConfig } from './models/themeConfig';
export { parseThemeColorValue, parseColorValue } from './models/themeColorValue';
export type { ThemeColorValue } from './models/themeColorValue';
export { parseThemeFontFace } from './models/themeFontFace';
export type { ThemeFontFace } from './models/themeFontFace';
export { parseThemeStyle } from './models/themeStyle';
export type { ThemeStyle } from './models/themeStyle';
export {
  parseThemeStylesPage,
  hasMoreStyles,
  EMPTY_STYLES_PAGE,
} from './models/themeStylesPage';
export type { ThemeStylesPage } from './models/themeStylesPage';

// --- Store -------------------------------------------------------------------
export { ThemeStore } from './store/themeStore';
export type { ThemeSnapshot, ThemeStoreOptions } from './store/themeStore';
export { StylesPager } from './store/stylesPager';
export type { StylesPagerOptions, StylesPagerState } from './store/stylesPager';
export {
  LAST_GOOD_KEY,
  SELECTED_DESIGN_KEY,
  readLastGood,
  writeLastGood,
  readSelectedDesignId,
  writeSelectedDesignId,
} from './store/persistence';

// --- Colour ------------------------------------------------------------------
export { rgba, toCss, withAlpha, alphaBlend, hslLightness } from './theme/color';
export type { Rgba } from './theme/color';

// --- Resolvers (usable OUTSIDE React — a token module needs these) -----------
export {
  themeColor,
  themePaletteEntry,
  themeToken,
  themeMode,
  themeImageSrc,
  themeIconUrl,
  themeFontFamily,
  themeText,
  themeDesignName,
} from './theme/resolvers';
export { ThemeDerivation } from './theme/themeDerivation';
export type { ThemeDerivationKey } from './theme/themeDerivation';
export { EngineTokens } from './theme/engineTokens';
export { loadFontFamily, fontStack, googleFontsCssUrl } from './theme/fontLoader';
export { computeAssetTargets, warmThemeAssets } from './theme/assetWarmer';
export type { AssetTargets } from './theme/assetWarmer';

// --- React bindings ----------------------------------------------------------
export { ThemeProvider } from './react/ThemeProvider';
export type { ThemeProviderProps } from './react/ThemeProvider';
export { ThemedImage } from './react/ThemedImage';
export type { ThemedImageProps } from './react/ThemedImage';
export { ThemeIcon } from './react/ThemeIcon';
export type { ThemeIconProps } from './react/ThemeIcon';
export {
  useThemeSnapshot,
  useThemeConfig,
  useThemeReady,
  useActiveDesign,
  useThemeColor,
  useThemePaletteEntry,
  useThemeToken,
  useThemeMode,
  useThemeText,
  useThemeDesignName,
  useThemeFontFamily,
  useThemeImageSrc,
  useThemeIconUrl,
} from './react/hooks';
export type { ThemeColorQuery } from './react/hooks';
export { useStylesPager } from './react/useStylesPager';
export type { StylesPagerView } from './react/useStylesPager';

// --- Motion ------------------------------------------------------------------
export { CelebrationTimings } from './motion/celebrationTimings';
export {
  EASE_OUT,
  EASE_OUT_QUART,
  easeOutQuart,
  SCALE_REVEAL_START_SCALE,
} from './motion/curves';
