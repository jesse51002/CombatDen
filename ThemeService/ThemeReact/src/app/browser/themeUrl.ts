// Ports the URL half of
// ../../../../../CRM/lib/features/members/presentation/widgets/member_app/
// theme_tab/live_theme_preview_tab.dart — `_themeFromUrl` (lines 117-125) and
// `_syncUrl` (lines 130-141).
//
// Flutter reaches these through `Uri.base` and
// `SystemNavigator.routeInformationUpdated`; the browser's own History API is
// what both of those wrap.

/** `clean` — an empty value is the same as an absent one. */
function clean(value: string | null | undefined): string | null {
  return value !== null && value !== undefined && value !== '' ? value : null;
}

/**
 * Reads `?theme=…`, tolerating either URL strategy: hash (the route + query
 * live in the fragment) or path (a real query string).
 */
export function themeFromUrl(): string | null {
  const fragment = window.location.hash.replace(/^#/, '');
  if (fragment !== '') {
    const queryStart = fragment.indexOf('?');
    if (queryStart >= 0) {
      const fromHash = clean(new URLSearchParams(fragment.slice(queryStart)).get('theme'));
      if (fromHash !== null) return fromHash;
    }
  }
  return clean(new URLSearchParams(window.location.search).get('theme'));
}

/**
 * The deep-linked theme, read ONCE at module load.
 *
 * Ports `late final String? _urlTheme = _themeFromUrl()`: the value must be the
 * one the visitor arrived with, and `syncThemeUrl` starts rewriting the address
 * bar as soon as the browser mounts. Two consumers read it — the seed design
 * `<ThemeProvider>` boots on, and the initial mode (a deep link opens straight
 * into the phone view instead of the library) — and they must agree.
 */
export const INITIAL_URL_THEME: string | null = themeFromUrl();

/**
 * Mirrors the current view into the address bar. **Replace, not push**, so
 * theme-hopping doesn't stack a history entry per theme — the back button
 * should leave the browser, not walk back through thirty previews.
 *
 * Only the phone view carries a theme; the library clears it.
 */
export function syncThemeUrl(theme: string | null): void {
  const path = window.location.pathname;
  const url = theme === null || theme === '' ? path : `${path}?theme=${encodeURIComponent(theme)}`;
  window.history.replaceState(window.history.state, '', url);
}
