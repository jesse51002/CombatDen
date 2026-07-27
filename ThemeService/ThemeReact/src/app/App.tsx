// The standalone theme browser's shell.
//
// Ports the composition ../../../../CRM/lib/main_theme_browser.dart performs:
// the landing page's sticky nav (ported verbatim in ./chrome/) over the
// theme-browser module (./browser/ThemeBrowser.tsx), with the customization
// engine booted around both.
//
// <ThemeProvider> is the `FutureBuilder<void>(future: _engineReady, …)` at
// live_theme_preview_tab.dart:172 — the gate that holds the preview back until
// the runtime has settled. It carries NO value: every hook below reads the
// module-singleton store directly (see ../../CLAUDE.md).

import { useEffect, useState } from 'react';
import { ThemeProvider, loadFontFamily } from 'theme-react';

import styles from './App.module.css';
import { INITIAL_URL_VIEW, syncViewUrl, type AppView } from './appUrl';
import { ThemeBrowser } from './browser/ThemeBrowser';
import { INITIAL_URL_THEME } from './browser/themeUrl';
import { GWNav } from './chrome/GWNav';
import { APP_ID, SEED_DESIGN_ID } from './config';
import { InspectView } from './inspect/InspectView';
import {
  EXPECTED_COLORS,
  EXPECTED_FONTS,
  EXPECTED_ICONS,
  EXPECTED_IMAGES,
  EXPECTED_TEXT,
} from './showcase/showcaseSlots';
import { StudioView } from './studio/StudioView';
import { ADM } from './tokens/adminTokens';
import { ViewTabs } from './ViewTabs';
import { AppSpinner } from './widgets/AppSpinner';

// Geist is the CHROME's typeface (the CRM's `baseFont`, the landing page's
// `GW.sans`) — not a theme slot, so nothing in the runtime will fetch it. The
// same Google Fonts injection the theme's own font slots use loads it once.
// The theme's fonts are loaded separately, by `useThemeFontFamily`.
loadFontFamily(ADM.fontFamily);

export function App() {
  // The top-level view. A deep link opens straight onto it; from here on the
  // address bar follows the state (../appUrl.ts), which is what lets a demo be
  // handed over as a URL rather than a click path.
  const [view, setView] = useState<AppView>(INITIAL_URL_VIEW);

  useEffect(() => {
    syncViewUrl(view);
  }, [view]);

  return (
    <div className={styles.app}>
      <GWNav />
      <ViewTabs view={view} onChange={setView} />
      <main className={styles.main}>
        <ThemeProvider
          appId={APP_ID}
          // The design the engine boots on: the deep-linked one, else the seed.
          // A previous visit's sticky selection outranks both (ThemeStore's
          // fallback ladder), which ThemeBrowser corrects back on mount.
          designId={INITIAL_URL_THEME ?? SEED_DESIGN_ID}
          // The slot manifest the showcase screens consume — Dart passes the
          // same `ShowcaseSlots.expected*` lists into `ThemeRuntime.initialize`.
          // They are used ONLY for the store's loud missing-slot warning, which
          // is why the browser declares exactly what the phone renders and not
          // the member app's whole inventory.
          expectedColors={EXPECTED_COLORS}
          expectedImages={EXPECTED_IMAGES}
          expectedFonts={EXPECTED_FONTS}
          expectedText={EXPECTED_TEXT}
          expectedIcons={EXPECTED_ICONS}
          fallback={<CenteredSpinner />}
        >
          {/* All three views sit INSIDE the gate: the inspector reads the
              resolved theme, and the studio previews what it just produced,
              so neither can render before the runtime has settled. */}
          {view === 'inspect' ? (
            <InspectView />
          ) : view === 'studio' ? (
            <StudioView />
          ) : (
            <ThemeBrowser />
          )}
        </ThemeProvider>
      </main>
    </div>
  );
}

/** Ports `_CenteredSpinner` (live_theme_preview_tab.dart:308-324). */
function CenteredSpinner() {
  return (
    <div className={styles.loading}>
      <AppSpinner size={ADM.spinnerSizeLarge} strokeWidth={2} />
    </div>
  );
}
