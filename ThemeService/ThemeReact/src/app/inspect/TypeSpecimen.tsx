// One font slot, set as a specimen rather than reported as a string.
//
// The family NAME rendered in the face it names, over a character line, is the
// same data doing the work a listing cannot: a buyer sees the pairing decision
// instead of reading that one was made.
//
// The DESCRIPTION is why this file now looks like ./ColorRole.tsx. The run
// writes a paragraph on why each face was picked and a name of its own for it
// ("Athletic Modern"), exactly as it does for every colour — and until the API
// carried `font_set`, the wire threw both away and left type as the one section
// on the sheet that could not make its own argument. It is body copy at reading
// measure here, set in the face it describes, for the same reason a colour's
// prose is: it is the engine's reasoning, and nothing else on the page carries
// it.

import { fontStack } from 'theme-react';

import type { FontView } from './artifactModel';
import styles from './TypeSpecimen.module.css';

export interface TypeSpecimenProps {
  slot: string;
  /** `null` when the pipeline produced no family for this slot. */
  face: FontView | null;
  /**
   * A generated line to set at headline scale, or `null` for a face whose own
   * description already IS its paragraph of running copy.
   */
  sample: string | null;
}

/** Enough of the alphabet to judge a face, short enough to hold one line. */
const UPPERCASE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const LOWERCASE = 'abcdefghijklmnopqrstuvwxyz';
const FIGURES = '0123456789 £$ .,;:!?—';

export function TypeSpecimen({ slot, face, sample }: TypeSpecimenProps) {
  if (face === null) {
    return (
      <article className={styles.specimen}>
        <header className={styles.caption}>
          <p className={styles.slot}>{slot}</p>
        </header>
        <p className={styles.missing}>No family was produced for this slot.</p>
      </article>
    );
  }
  const setInFace = { fontFamily: fontStack(face.family) };
  return (
    <article className={styles.specimen}>
      {/*
        Slot id left, Google's own classification right — the plate caption
        from ./AssetPlates.tsx, reused rather than restyled. Both are mono
        micro-labels naming a fact about the specimen beside them, so they are
        the same object and get the same row.
      */}
      <header className={styles.caption}>
        <p className={styles.slot}>{slot}</p>
        {face.category === '' ? null : <p className={styles.category}>{face.category}</p>}
      </header>
      <p className={styles.family} style={setInFace}>
        {face.family}
      </p>
      {/* Omitted rather than filled when absent: the family above already
          names the face, so a placeholder would only assert a hole. */}
      {face.displayName === '' ? null : (
        <p className={styles.faceName} style={setInFace}>
          {face.displayName}
        </p>
      )}
      <div className={styles.characters} style={setInFace} aria-hidden>
        <span>{UPPERCASE}</span>
        <span>{LOWERCASE}</span>
        <span>{FIGURES}</span>
      </div>
      {sample === null ? null : (
        <p className={styles.line} style={setInFace}>
          {sample}
        </p>
      )}
      {face.description === '' ? (
        <p className={styles.noProse}>No description was produced for this face.</p>
      ) : (
        <p className={styles.description} style={setInFace}>
          {face.description}
        </p>
      )}
    </article>
  );
}
