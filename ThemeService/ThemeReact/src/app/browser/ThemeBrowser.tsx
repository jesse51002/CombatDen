// Ports ../../../../../CRM/lib/features/members/presentation/widgets/
// member_app/theme_tab/live_theme_preview_tab.dart — the reusable
// theme-browser MODULE.
//
// Defaults to the themes library (filter + search + grid). Picking a theme card
// switches to the phone-frame preview; the side pane's "Back to library" link
// returns. Below `SIDE_BY_SIDE_MIN_WIDTH` the phone goes full-bleed — no side
// list, no horizontal layout — and carries its own back button; at or above it
// the phone sits beside the scrollable picker.
//
// The Dart widget hosts BOTH the admin's embedded tab and the standalone
// browser, and its only host-specific knob is `routePath`. Here there is one
// host, so the path is the document's own (see ./themeUrl.ts).
//
// WHAT IS NOT PORTED: everything gated on `selectedGym.gymId != null` — the
// admin's gym identity threaded into the mock, the gym-profile dialog, and the
// `FutureBuilder` around `ThemeRuntime.initialize`. This browser has no gym,
// and the bootstrap gate is <ThemeProvider> in ../App.tsx, which is the same
// FutureBuilder expressed once for the whole tree.

import { useEffect, useState } from 'react';
import { useActiveDesign } from 'theme-react';

import { SIDE_BY_SIDE_MIN_WIDTH, SIDE_PANE_WIDTH } from '../config';
import { AppOutlineButton } from '../widgets/AppOutlineButton';
import { cx } from '../widgets/cx';
import { useElementSize } from '../widgets/useElementSize';

import { LibraryView } from './LibraryView';
import styles from './ThemeBrowser.module.css';
import { ThemeGrid } from './ThemeGrid';
import { ThemePreviewPane } from './ThemePreviewPane';
import { INITIAL_URL_THEME, syncThemeUrl } from './themeUrl';

type Mode = 'library' | 'phone';

export function ThemeBrowser() {
  // A deep-linked theme opens straight into the phone view; a reload while
  // previewing therefore restores that view rather than dropping back to the
  // library. Read once, at mount — `syncThemeUrl` rewrites the address bar from
  // here on.
  const [mode, setMode] = useState<Mode>(() => (INITIAL_URL_THEME !== null ? 'phone' : 'library'));
  const { id: liveDesignId } = useActiveDesign();
  // The root is the page-width container, so the viewport is an exact-enough
  // first frame; the ResizeObserver corrects it on commit.
  const [measureRef, { width }] = useElementSize<HTMLDivElement>({
    width: window.innerWidth,
    height: window.innerHeight,
  });

  // The tail of `_bootstrap` — correcting a STICKY localStorage selection that
  // outranks the deep-linked seed — now lives ONCE in ../App.tsx, as
  // <DeepLinkTheme> above every view. It was here while the library was the
  // only view; arriving straight at another one then silently ignored `?theme=`.

  // Mirror the current view into the address bar on every theme switch (from
  // the library grid or the side pane) and on every mode change. Only the phone
  // view carries a theme; the library clears it.
  useEffect(() => {
    syncThemeUrl(mode === 'phone' ? liveDesignId : null);
  }, [mode, liveDesignId]);

  const sideBySide = width >= SIDE_BY_SIDE_MIN_WIDTH;

  return (
    <div ref={measureRef} className={cx(styles.browser, mode === 'phone' && styles.phone)}>
      {mode === 'library' ? (
        <LibraryView onPicked={() => setMode('phone')} />
      ) : sideBySide ? (
        // Wide: phone preview beside the scrollable theme picker.
        <div className={styles.split}>
          <ThemePreviewPane />
          <div className={styles.sidePane} style={{ width: `${SIDE_PANE_WIDTH}px` }}>
            <ThemeGrid onBackToLibrary={() => setMode('library')} />
          </div>
        </div>
      ) : (
        // Mobile / narrow: the phone is the whole thing. The side pane's back
        // link is gone, so the phone gets its own, stacked above it.
        <div className={styles.stack}>
          <div className={styles.backRow}>
            <AppOutlineButton text="← Back to library" onPressed={() => setMode('library')} />
          </div>
          <ThemePreviewPane />
        </div>
      )}
    </div>
  );
}
