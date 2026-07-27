// The app's TOP-LEVEL view routing.
//
// This has no Flutter counterpart to port: the CRM's theme surface is a single
// tab, so `browser/themeUrl.ts` (which does port it) only ever had to carry a
// theme. Two further views — the artifact inspector and the generation studio —
// exist only here, so their routing is native rather than a port.
//
// Kept OUT of `browser/themeUrl.ts` on purpose: that module is the URL half of
// one ported widget, and the view a visitor is on is not that widget's concern.
// The two write the same address bar and therefore share one rule, stated once
// here and honoured there: *merge* into the existing query string, never rebuild
// it, or each would erase the other's parameter.

/**
 * The three top-level surfaces.
 *
 * `browse` is the default and is deliberately ABSENT from the URL — a bare
 * `/` is the library, so the address a visitor shares stays clean and an
 * unknown `?view=` degrades to it rather than erroring.
 */
export type AppView = 'browse' | 'inspect' | 'studio';

const VIEW_PARAM = 'view';

const VIEWS: readonly AppView[] = Object.freeze(['browse', 'inspect', 'studio']);

function isAppView(value: string | null): value is AppView {
  return value !== null && (VIEWS as readonly string[]).includes(value);
}

/**
 * Reads `?view=…`, tolerating either URL strategy (hash or real query string)
 * exactly as `themeFromUrl` does, so a deep link works under both.
 */
export function viewFromUrl(): AppView {
  const fragment = window.location.hash.replace(/^#/, '');
  if (fragment !== '') {
    const queryStart = fragment.indexOf('?');
    if (queryStart >= 0) {
      const fromHash = new URLSearchParams(fragment.slice(queryStart)).get(VIEW_PARAM);
      if (isAppView(fromHash)) return fromHash;
    }
  }
  const fromQuery = new URLSearchParams(window.location.search).get(VIEW_PARAM);
  return isAppView(fromQuery) ? fromQuery : 'browse';
}

/**
 * The deep-linked view, read ONCE at module load — the mirror of
 * `INITIAL_URL_THEME`, and for the same reason: `syncViewUrl` starts rewriting
 * the address bar as soon as the app mounts, so the arrival value has to be
 * captured before that happens.
 */
export const INITIAL_URL_VIEW: AppView = viewFromUrl();

/**
 * Mirrors the current view into the address bar.
 *
 * **Replace, not push** (the same call `syncThemeUrl` makes) so switching views
 * doesn't stack history entries, and **merge** so the `?theme=` the browser
 * owns survives a view change untouched.
 */
export function syncViewUrl(view: AppView): void {
  const params = new URLSearchParams(window.location.search);
  if (view === 'browse') params.delete(VIEW_PARAM);
  else params.set(VIEW_PARAM, view);
  const query = params.toString();
  const url = query === '' ? window.location.pathname : `${window.location.pathname}?${query}`;
  window.history.replaceState(window.history.state, '', url);
}
