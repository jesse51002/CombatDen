// The masthead band: every derived colour in the theme, in one object.
//
// This is the page's whole argument compressed into one element. Four swatches
// read as a colour scheme; twenty-eight hard-edged bands, grouped and ticked by
// the role they came from, read as a system that was computed. It is the only
// thing on the page that moves, and it moves once.

import { toCss } from 'theme-react';

import type { SpectrumBand } from './artifactModel';
import styles from './Spectrum.module.css';

export interface SpectrumProps {
  bands: readonly SpectrumBand[];
}

export function Spectrum({ bands }: SpectrumProps) {
  if (bands.length === 0) return null;
  return (
    <div className={styles.spectrum}>
      <div className={styles.bands}>
        {bands.map((band, index) => (
          <div
            // Role + derivation is unique across the whole band, and stable
            // across a theme switch — so React re-paints the same 28 nodes
            // rather than tearing them down and replaying the entrance.
            key={`${band.role}_${band.key}`}
            className={styles.band}
            style={{
              background: toCss(band.color),
              // Drives the entrance stagger; see the stylesheet.
              ['--band-index' as string]: String(index),
            }}
          />
        ))}
      </div>
      <ol className={styles.ticks}>
        {groupRuns(bands).map((run) => (
          <li key={run.role} className={styles.tick} style={{ flexGrow: run.length }}>
            {run.role}
          </li>
        ))}
      </ol>
    </div>
  );
}

interface Run {
  readonly role: string;
  readonly length: number;
}

/**
 * Consecutive bands of the same role, so the tick row underneath can span each
 * group at exactly the group's own width. Exported-free on purpose: it is two
 * lines and only this file's `flexGrow` needs it.
 */
function groupRuns(bands: readonly SpectrumBand[]): readonly Run[] {
  const runs: Run[] = [];
  for (const band of bands) {
    const last = runs.at(-1);
    if (last !== undefined && last.role === band.role) {
      runs[runs.length - 1] = { role: last.role, length: last.length + 1 };
    } else {
      runs.push({ role: band.role, length: 1 });
    }
  }
  return runs;
}
