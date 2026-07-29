// A once-a-second clock, for the only thing on this page that must move while
// nothing is arriving.
//
// A generation run is minutes long and five nodes deep at a time, and between
// two `node_finished` events NOTHING changes on the wire — that silence is
// exactly what makes a progress bar a dead demo. One tick shared by every
// running node turns that silence into five counters climbing, which is
// information rather than decoration, so it survives `prefers-reduced-motion`.
//
// ONE interval for the whole sheet, not one per node: N intervals would each
// re-render the tree anyway, and they would tick out of phase with each other.
//
// `setState` lives inside the interval CALLBACK, never in the effect body —
// the React Compiler's `set-state-in-effect` rule is an error in this package.

import { useEffect, useState } from 'react';

/** Seconds are the smallest unit anything here prints. */
const TICK_MS = 1000;

/**
 * `Date.now()`, refreshed every second while `active`.
 *
 * Frozen at its last value when `active` goes false, so a finished run stops
 * costing renders and the numbers it settled on stay put.
 */
export function useNowTick(active: boolean): number {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (!active) return;
    const id = window.setInterval(() => {
      setNow(Date.now());
    }, TICK_MS);
    return () => {
      window.clearInterval(id);
    };
  }, [active]);

  return now;
}
