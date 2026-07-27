// The delivery half of ./showcaseTokens.ts (which ports
// ../../../../../CRM/lib/showcase/showcase_tokens.dart). No Dart counterpart
// file: Flutter re-reads `ShowcaseTokens.primaryColor` inside every `build`, so
// a `ListenableBuilder` at the top of the tree re-themes everything for free.
//
// The web's equivalent is CSS custom properties. This component resolves the
// whole token surface ONCE and writes it as ~67 `--sc-*` variables onto a
// SINGLE element — the phone screen's root. Every showcase `.module.css`
// underneath reads `var(--sc-…)` and nothing else, so `selectDesign` re-skins
// all seven screens by rewriting variables on that one element: the cascade
// does the work Flutter's rebuild does, and the screens themselves never
// subscribe to the theme for a colour, a font or a measurement.
//
// This is also why the screens below are cheap to re-render: only THIS
// component subscribes to the store for the token surface. Its `children` are
// an element passed in from the caller, so a theme change updates one `style`
// object and React bails out of the subtree entirely.
//
// Images, icons and copy are the deliberate exception — a `src`, a mask URL and
// a string are not styles — and resolve through the library's <ThemedImage> /
// <ThemeIcon> / `useThemeText` at their own call sites.

import type { CSSProperties, ReactNode } from 'react';
import { useThemeFontFamily, useThemeSnapshot } from 'theme-react';

import { SLOT_FONT_BODY, SLOT_FONT_DISPLAY } from './showcaseSlots';
import { FALLBACK_FONT_FAMILY, showcaseCssVars, showcaseStyle } from './showcaseTokens';

export interface ShowcaseThemeVarsProps {
  children: ReactNode;
  className?: string | undefined;
  /** Merged AFTER the variables, so a caller can still position the root. */
  style?: CSSProperties | undefined;
}

export function ShowcaseThemeVars({ children, className, style }: ShowcaseThemeVarsProps) {
  const snapshot = useThemeSnapshot();
  // `useThemeFontFamily` resolves the slot AND injects the family's Google
  // Fonts stylesheet via the library's `loadFontFamily`. Naming a family in a
  // `font-family` declaration does nothing on the web until that stylesheet is
  // in the document — this is the call that makes the theme's type real.
  const displayFamily = useThemeFontFamily(SLOT_FONT_DISPLAY, FALLBACK_FONT_FAMILY);
  const bodyFamily = useThemeFontFamily(SLOT_FONT_BODY, FALLBACK_FONT_FAMILY);

  const vars = showcaseCssVars(snapshot, displayFamily, bodyFamily);

  return (
    <div className={className} style={showcaseStyle(vars, style)}>
      {children}
    </div>
  );
}
