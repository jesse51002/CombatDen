// One font slot, set as a specimen rather than reported as a string.
//
// The wire gives a family NAME and nothing else — `fonts: {display: "Space
// Grotesk"}` — so a listing would be two words of Geist and would prove
// nothing. The name rendered in the face it names, over a character line and a
// sentence the same run generated, is the same data doing the work: a buyer can
// see the pairing decision, not just read that one was made.

import { fontStack } from 'theme-react';

import styles from './TypeSpecimen.module.css';

export interface TypeSpecimenProps {
  slot: string;
  /** `null` when the pipeline produced no family for this slot. */
  family: string | null;
  /** Copy from this same run, set in this face. */
  sample: string;
  /** Body faces get a paragraph; display faces get a single large line. */
  asParagraph: boolean;
}

/** Enough of the alphabet to judge a face, short enough to hold one line. */
const UPPERCASE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const LOWERCASE = 'abcdefghijklmnopqrstuvwxyz';
const FIGURES = '0123456789 £$ .,;:!?—';

export function TypeSpecimen({ slot, family, sample, asParagraph }: TypeSpecimenProps) {
  if (family === null) {
    return (
      <article className={styles.specimen}>
        <p className={styles.slot}>{slot}</p>
        <p className={styles.missing}>No family was produced for this slot.</p>
      </article>
    );
  }
  const face = { fontFamily: fontStack(family) };
  return (
    <article className={styles.specimen}>
      <p className={styles.slot}>{slot}</p>
      <p className={styles.family} style={face}>
        {family}
      </p>
      <div className={styles.characters} style={face} aria-hidden>
        <span>{UPPERCASE}</span>
        <span>{LOWERCASE}</span>
        <span>{FIGURES}</span>
      </div>
      <p className={asParagraph ? styles.paragraph : styles.line} style={face}>
        {sample}
      </p>
    </article>
  );
}
