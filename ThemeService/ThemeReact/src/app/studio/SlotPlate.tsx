// One image slot, as a plate that develops.
//
// THE PLATE EXISTS BEFORE THE IMAGE DOES. Every slot in a level is laid out
// empty the moment that level starts, so the run's progress is SPATIAL — a
// reader watching a demo sees seven frames and three filled, and knows what is
// left without a percentage that could not have been honest anyway (nobody has
// measured how long a run takes).
//
// THE PLATE IS PAINTED IN THE GROUND THE ART WAS AUTHORED FOR, the same
// correctness decision ../inspect/AssetPlates.tsx makes and for the same
// reason: these are transparent PNGs made for the theme's own background, so a
// pale mark on this page's near-white chrome is invisible and a dark one on it
// is a lie about what the member sees. The ground resolves in three steps as
// the run learns more — the brief's light/dark choice while it runs, then the
// generated background once the finished theme is loaded.
//
// The bytes come from the STUDIO's image endpoint, not the read API's: the
// read API loads the run's `output.yaml` first and that file is written only
// when the whole run finishes, so mid-run every request there 404s.

import { useState } from 'react';

import { cx } from '../widgets/cx';

import type { RunNode } from './runFold';
import { nodeTiming } from './runFold';
import styles from './SlotPlate.module.css';
import { runImageUrl } from './studioApi';

export interface SlotPlateProps {
  runId: string;
  slot: RunNode;
  /** The shared 1s tick, so every running plate counts in step. */
  now: number;
  /** CSS colour of the ground this asset was authored against. */
  ground: string;
  /** The ink that reads on that ground — plate text is never a chrome token. */
  ink: string;
}

export function SlotPlate({ runId, slot, now, ground, ink }: SlotPlateProps) {
  return (
    <figure className={styles.plate}>
      <div
        className={cx(styles.surface, slot.state === 'running' && styles.running)}
        // `color` as well as the ground: the plate's working bar is drawn in
        // `currentcolor`, so the one ink resolved here serves both the note and
        // the indicator instead of each picking its own.
        style={{ background: ground, color: ink }}
      >
        {slot.state === 'done' ? (
          <PlateImage runId={runId} slot={slot.key} />
        ) : (
          <PlateNote slot={slot} />
        )}
      </div>
      <figcaption className={styles.caption}>
        <span className={styles.slot}>{slot.key}</span>
        <span className={styles.timing}>{nodeTiming(slot, now)}</span>
      </figcaption>
    </figure>
  );
}

function PlateImage({ runId, slot }: { runId: string; slot: string }) {
  const [failed, setFailed] = useState(false);
  if (failed) {
    return <span className={styles.note}>not on disk</span>;
  }
  return (
    <img
      className={styles.art}
      // `no-store` on the endpoint, so this is always the newest bytes.
      src={runImageUrl(runId, slot)}
      // The slot id is the only honest description available: the pipeline
      // ships no alt text, and inventing one would describe art nobody read.
      alt={slot}
      decoding="async"
      onError={() => {
        setFailed(true);
      }}
    />
  );
}

/**
 * The plate's own status, drawn in the ink derived from ITS ground rather than
 * a chrome token — a fixed grey that reads on a near-black plate disappears on
 * a near-white one.
 */
function PlateNote({ slot }: { slot: RunNode }) {
  if (slot.state === 'running') return null;
  const label =
    slot.state === 'queued' ? 'queued' : slot.state === 'failed' ? 'failed' : 'not produced';
  return (
    <span
      className={styles.note}
      // The engine's own message, for the one reader who wants it. It is a
      // provider stack trace, not a sentence — it belongs in a title, not on
      // the sheet.
      title={slot.error ?? undefined}
    >
      {label}
    </span>
  );
}
