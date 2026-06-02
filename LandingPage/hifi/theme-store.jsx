// theme-store.jsx — global brand-theme state for the live mocks.
//
// This is NOT the product's CustomizationEngine. It is a presentation-only
// store: a hardcoded list of brand themes plus a hardcoded {theme -> image}
// dict. A global theme is held in React context so a single theme change
// re-skins every single-device mock on the page at once (accent + screen
// image). The §3 theme rail is the exception — it shows many fixed themes
// side by side, so ThemePreview stays prop-driven.
//
// Exports THEMES, THEME_ASSETS, ThemeProvider, useTheme, ThemeSwitcher.

const THEMES = [
  { id: 'tidal',  name: 'Tidal Strength',     accent: '#2A67BD', dark: false },
  { id: 'forge',  name: 'Forge Athletic',     accent: '#E5484D', dark: false },
  { id: 'refrm',  name: 'Reformer Pilates',   accent: '#1F8A5B', dark: false },
  { id: 'pulse',  name: 'Pulse Studio',       accent: '#C0269B', dark: false },
  { id: 'sunup',  name: 'Sunup Conditioning', accent: '#E07A1F', dark: false },
  { id: 'coast',  name: 'Coast Rowing',       accent: '#0E8FA8', dark: false },
  { id: 'night',  name: 'Nightshift Barbell', accent: '#8B7CF6', dark: true  },
  { id: 'clay',   name: 'Clay House',         accent: '#C2603D', dark: false },
  { id: 'apex',   name: 'Apex Climb',         accent: '#5B57E0', dark: true  },
];

// Hardcoded theme -> screen image/gif. Placeholder assets for now (no real
// per-brand renders exist yet); this dict is the single edit point when they
// land. Mocks fall back to a CSS striped placeholder when a theme is absent.
const THEME_ASSETS = {
  tidal: 'assets/landing/pil-1.jpeg',
  forge: 'assets/landing/pil-2.jpeg',
  refrm: 'assets/landing/pil-3.jpeg',
  pulse: 'assets/landing/pil-4.jpeg',
  sunup: 'assets/landing/pil-2.jpeg',
  coast: 'assets/landing/pil-3.jpeg',
  night: 'assets/landing/pil-1.jpeg',
  clay:  'assets/landing/pil-4.jpeg',
  apex:  'assets/landing/pil-3.jpeg',
};

const ThemeContext = React.createContext(null);

function ThemeProvider({ children, initial = 'tidal' }) {
  const [activeId, setActiveId] = React.useState(initial);
  const theme = THEMES.find((t) => t.id === activeId) || THEMES[0];
  const value = {
    theme,
    asset: THEME_ASSETS[theme.id] || null,
    activeId,
    setTheme: setActiveId,
    themes: THEMES,
  };
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

// Returns { theme, asset, activeId, setTheme, themes }. Safe outside a provider
// (falls back to the first theme) so a mock can render standalone.
function useTheme() {
  const ctx = React.useContext(ThemeContext);
  if (ctx) return ctx;
  const theme = THEMES[0];
  return { theme, asset: THEME_ASSETS[theme.id] || null, activeId: theme.id, setTheme: () => {}, themes: THEMES };
}

// Minimal swatch row. Click a brand to re-skin every live mock on the page.
// Intentionally simple (founder: "doesn't have to be the prettiest") — a
// functional control that exercises the global theme state.
function ThemeSwitcher({ style = {} }) {
  const { themes, activeId, setTheme } = useTheme();
  return (
    <div role="radiogroup" aria-label="Preview your gym's brand" style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap', justifyContent: 'center', ...style }}>
      <span style={{ fontFamily: GW.mono, fontSize: 11, letterSpacing: 0.4, textTransform: 'uppercase', color: GW.inkFaint, marginRight: 2 }}>Try a brand</span>
      {themes.map((t) => {
        const on = t.id === activeId;
        return (
          <button
            key={t.id} role="radio" aria-checked={on} title={t.name} onClick={() => setTheme(t.id)}
            style={{
              width: 26, height: 26, borderRadius: 999, cursor: 'pointer', padding: 0,
              background: t.accent, border: '2px solid #fff',
              outline: on ? `2px solid ${gwRgba(t.accent, 0.9)}` : '2px solid transparent', outlineOffset: 1,
              boxShadow: on ? `0 4px 12px -2px ${gwRgba(t.accent, 0.6)}` : '0 1px 2px rgba(20,22,40,0.18)',
              transform: on ? 'scale(1.08)' : 'scale(1)', transition: 'transform .18s cubic-bezier(.22,1,.36,1), box-shadow .18s',
            }}
          />
        );
      })}
    </div>
  );
}

Object.assign(window, { THEMES, THEME_ASSETS, ThemeProvider, useTheme, ThemeSwitcher });
