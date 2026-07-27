import {
  DEFAULTS,
  ThemeProvider,
  resolveBackendBaseUrl,
  resolveThemeBaseUrl,
  rgba,
  themeToken,
  toCss,
  useActiveDesign,
  useThemeConfig,
  useThemeMode,
} from 'theme-react';

import { APP_ID, SEED_DESIGN_ID } from './config';

// SCAFFOLD. The real shell — GWNav + the library grid + the phone preview —
// lands in the next phases. This renders the LIVE theme through the library so
// the toolchain, the alias, the env plumbing AND the runtime are provably
// working end to end.

/** The palette roles worth eyeballing: the base ones plus the orphan tokens. */
const SWATCHES = ['primary', 'background', 'text', 'accent', 'card', 'popup', 'divider'];

/** Visible magenta — a swatch in this colour means the role did not resolve. */
const UNRESOLVED = rgba(255, 0, 255);

export function App() {
  const themeBaseUrl = resolveThemeBaseUrl();
  const backendBaseUrl = resolveBackendBaseUrl();

  return (
    <main>
      <h1>ThemeReact</h1>
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
      <ThemeProvider appId={APP_ID} designId={SEED_DESIGN_ID} fallback={<p>Loading theme…</p>}>
        <ThemePeek />
      </ThemeProvider>
    </main>
  );
}

function ThemePeek() {
  const { id, name } = useActiveDesign();
  const mode = useThemeMode();
  const config = useThemeConfig();

  if (config === null) {
    return <p>No theme loaded. Is ThemeService running (cd ThemeService &amp;&amp; make api)?</p>;
  }

  return (
    <section>
      <h2>{name ?? 'Unnamed design'}</h2>
      <p>
        {id ?? '—'} · {mode} · {Object.keys(config.colors).length} colour slots ·{' '}
        {Object.keys(config.images).length} images · {Object.keys(config.icons).length} icons
      </p>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        {SWATCHES.map((key) => (
          <div key={key} style={{ width: 96 }}>
            <div
              style={{
                height: 48,
                borderRadius: 4,
                backgroundColor: toCss(themeToken(key, UNRESOLVED)),
              }}
            />
            <small>{key}</small>
          </div>
        ))}
      </div>
    </section>
  );
}
