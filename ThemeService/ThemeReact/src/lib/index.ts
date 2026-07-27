// theme-react — the public entry, and the ONLY export surface.
//
// This package is the React mirror of ../../ThemeFlutter (the `theme_flutter`
// Dart package): the white-label theme runtime. It fetches a tenant's resolved
// branding from the ThemeService API, keeps a last-good copy in localStorage,
// and exposes resolvers that never throw.
//
// It ships NO screens and NO bundled assets, exactly as ThemeFlutter doesn't —
// the showcase preview screens live in the consuming app (src/app/showcase/).
//
// SCAFFOLD: only the config surface exists so far. The runtime, models,
// resolvers, and React bindings land in the next phase; every export below
// is real and used, so `npm run typecheck` and both builds exercise the setup.

export { resolveThemeBaseUrl, resolveBackendBaseUrl, DEFAULTS } from './config';
export type { ThemeReactConfig } from './config';
