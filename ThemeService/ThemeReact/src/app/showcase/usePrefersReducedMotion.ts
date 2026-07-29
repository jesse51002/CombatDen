// Ports Flutter's `MediaQuery.disableAnimationsOf(context)`, which the
// showcase's animated surfaces read to drop their motion.
//
// A LOCAL COPY, deliberately. ../widgets/usePrefersReducedMotion.ts is the
// identical hook for the admin chrome, and the showcase island may not import
// from ../widgets (eslint.config.js Gate 2a) — the gate exists for the token
// modules, but it matches the whole directory, and duplicating 15 lines is the
// cheaper side of that trade. Keep the two in sync if either changes.
//
// A CSS `@media (prefers-reduced-motion: reduce)` block covers the purely
// decorative cases; this hook is for the ones where JS must also skip the work
// — here, not arming the booking celebration's loop timer at all.

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
