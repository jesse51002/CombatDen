// Ports ../../../../../LandingPage/hifi/ds.jsx — `MOBILE_Q` + `useIsMobile`,
// verbatim (only types added).
//
// From the Dart-side comment this hook exists for: the landing page is 100%
// inline styles, so a <style> media query can't override them without
// !important — responsiveness is JS-driven instead. Lazy-init from matchMedia
// so the first paint is already correct (no flash), and listen only to the
// `change` event so a re-render fires ONLY when the viewport crosses the
// breakpoint — never on scroll/resize within it.

import { useEffect, useState } from 'react';

export const MOBILE_Q = '(max-width: 768px)';

export function useIsMobile(q: string = MOBILE_Q): boolean {
  const [m, setM] = useState(() => window.matchMedia(q).matches);
  useEffect(() => {
    const mq = window.matchMedia(q);
    const h = (e: MediaQueryListEvent) => setM(e.matches);
    mq.addEventListener('change', h);
    return () => mq.removeEventListener('change', h);
  }, [q]);
  return m;
}
