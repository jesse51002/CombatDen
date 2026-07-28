// The sheet's index: what is on this page, how much of each, and where you are.
//
// A specimen sheet is long by design, and the demo it serves is spoken over —
// "show me the assets" has to be one click, not a scroll hunt. The rail is
// therefore wayfinding first and a contents list second, which is why each
// entry carries its own tally: the index doubles as the page's summary, so the
// answer to "how much does it generate?" is legible without scrolling at all.
//
// Hidden below 1024px, where the measure cannot spare the column — the section
// heads carry the same titles and tallies inline.

import { useEffect, useState } from 'react';

import styles from './IndexRail.module.css';

export interface RailEntry {
  readonly id: string;
  readonly label: string;
  readonly count: string;
}

export interface IndexRailProps {
  entries: readonly RailEntry[];
  /** Skip the smooth scroll when the visitor has asked for less motion. */
  reducedMotion: boolean;
}

export function IndexRail({ entries, reducedMotion }: IndexRailProps) {
  const active = useActiveSection(entries);
  return (
    <nav className={styles.rail} aria-label="On this page">
      <ol className={styles.list}>
        {entries.map((entry) => (
          <li key={entry.id}>
            <a
              className={styles.entry}
              href={`#${entry.id}`}
              aria-current={entry.id === active ? 'true' : undefined}
              onClick={(event) => {
                const target = document.getElementById(entry.id);
                if (target === null) return;
                // Let the anchor keep its semantics (focusable, copyable,
                // middle-clickable) and only take over the scroll itself, so
                // the jump can clear the sticky nav smoothly.
                event.preventDefault();
                target.scrollIntoView({
                  behavior: reducedMotion ? 'auto' : 'smooth',
                  block: 'start',
                });
              }}
            >
              <span className={styles.label}>{entry.label}</span>
              <span className={styles.count}>{entry.count}</span>
            </a>
          </li>
        ))}
      </ol>
    </nav>
  );
}

/**
 * The id of the section currently under the top of the viewport.
 *
 * An `IntersectionObserver` over a thin band just below the sticky nav rather
 * than a scroll handler: the callback fires only on a crossing, so there is no
 * per-frame work, and the state write happens in a subscription callback —
 * which is what `react-hooks`' `set-state-in-effect` rule permits and a
 * synchronous write in the effect body is not (see ../../../CLAUDE.md).
 */
function useActiveSection(entries: readonly IndexRailProps['entries'][number][]): string | null {
  const [active, setActive] = useState<string | null>(entries[0]?.id ?? null);
  // The ids are fixed for the life of the page; joining them gives the effect a
  // primitive dependency, so a re-render with an equal-but-new array does not
  // tear the observer down and rebuild it.
  const ids = entries.map((entry) => entry.id).join(',');

  useEffect(() => {
    const targets = ids
      .split(',')
      .map((id) => document.getElementById(id))
      .filter((element): element is HTMLElement => element !== null);
    if (targets.length === 0) return;

    const seen = new Set<string>();
    const observer = new IntersectionObserver(
      (records) => {
        for (const record of records) {
          if (record.isIntersecting) seen.add(record.target.id);
          else seen.delete(record.target.id);
        }
        // Several headings can share the band mid-scroll; the first in
        // DOCUMENT order is the one the reader has arrived at.
        const current = targets.find((target) => seen.has(target.id));
        if (current !== undefined) setActive(current.id);
      },
      {
        // A band from just under the sticky nav to 55% down the viewport. The
        // negative bottom margin is what stops the LAST section lighting up
        // the moment its heading enters from below.
        rootMargin: '-84px 0px -55% 0px',
        threshold: 0,
      },
    );
    for (const target of targets) observer.observe(target);
    return () => observer.disconnect();
  }, [ids]);

  return active;
}
