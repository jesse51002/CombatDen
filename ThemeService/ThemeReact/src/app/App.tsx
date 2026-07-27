import { DEFAULTS, resolveBackendBaseUrl, resolveThemeBaseUrl } from 'theme-react';

import { APP_ID, SEED_DESIGN_ID } from './config';

// SCAFFOLD. The real shell — GWNav + the library grid + the phone preview —
// lands in the next phases. This renders the resolved wiring so the toolchain,
// the library alias, and the env plumbing are all provably working end to end.
export function App() {
  const themeBaseUrl = resolveThemeBaseUrl();
  const backendBaseUrl = resolveBackendBaseUrl();

  return (
    <main>
      <h1>ThemeReact</h1>
      <p>Scaffold. The theme browser is not built yet.</p>
      <dl>
        <dt>App</dt>
        <dd>{APP_ID}</dd>
        <dt>Seed design</dt>
        <dd>{SEED_DESIGN_ID}</dd>
        <dt>ThemeService</dt>
        <dd>
          {themeBaseUrl}
          {themeBaseUrl === DEFAULTS.themeBaseUrl ? ' (default)' : ''}
        </dd>
        <dt>FastApiBackend</dt>
        <dd>
          {backendBaseUrl}
          {backendBaseUrl === DEFAULTS.backendBaseUrl ? ' (default)' : ''}
        </dd>
      </dl>
    </main>
  );
}
