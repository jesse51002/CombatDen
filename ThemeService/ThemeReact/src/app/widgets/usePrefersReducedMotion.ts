// Ports Flutter's `MediaQuery.disableAnimationsOf(context)` /
// `MediaQuery.maybeOf(context)?.disableAnimations`, which
// ../../../../../CRM/lib/features/members/presentation/widgets/member_app/
// theme_tab/theme_preview_pane.dart and .../shared/widgets/app_spinner.dart
// both read to drop their animations.
//
// Same subscription shape as ../chrome/useIsMobile.ts (matchMedia, lazy-init
// from `.matches`, `change` only). A CSS `@media (prefers-reduced-motion)`
// block covers the purely decorative cases; this hook is for the ones where
// JS must also skip the work — mounting the outgoing pane of a slide
// transition that would then never emit `animationend`.

import { useEffect, useState } from 'react';

const REDUCED_MOTION_Q = '(prefers-reduced-motion: reduce)';

export function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(() => window.matchMedia(REDUCED_MOTION_Q).matches);
  useEffect(() => {
    const mq = window.matchMedia(REDUCED_MOTION_Q);
    const handle = (event: MediaQueryListEvent) => setReduced(event.matches);
    mq.addEventListener('change', handle);
    return () => mq.removeEventListener('change', handle);
  }, []);
  return reduced;
}
