// The standalone theme browser's own constants.
//
// These are the app-specific inputs the library deliberately does not know
// about — the mirror of what CRM's live_theme_preview_tab.dart passes into
// ThemeRuntime.initialize (_kAppId / _kSeedDesignId at its lines 18-29).

/** The ThemeService app whose catalog this browser shows. */
export const APP_ID = 'combatden';

/**
 * The design loaded before the visitor has picked one. Only a first-paint
 * seed: a `?theme=` in the URL and a previous pick in localStorage both win.
 */
export const SEED_DESIGN_ID = 'ApexMMA';

/** The library↔phone layout switch, from live_theme_preview_tab.dart:24. */
export const SIDE_BY_SIDE_MIN_WIDTH = 700;

/** The phone-mode catalog pane, from live_theme_preview_tab.dart:26. */
export const SIDE_PANE_WIDTH = 300;
