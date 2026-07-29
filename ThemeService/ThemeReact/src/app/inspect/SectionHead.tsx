// One section's head on the specimen sheet: what the section holds, how much
// of it there is, and one line on what the pipeline did to produce it.
//
// The COUNT is the load-bearing half. A buyer's question on this page is "how
// much of a theme does this thing actually author?", and a running tally in the
// head answers it section by section without a stat block anywhere.

import styles from './SectionHead.module.css';

export interface SectionHeadProps {
  id: string;
  title: string;
  /** Right-hand tally, e.g. "4 roles · 28 derivations". Tabular figures. */
  count: string;
  children: string;
}

export function SectionHead({ id, title, count, children }: SectionHeadProps) {
  return (
    <header className={styles.head}>
      {/*
        The heading owns the anchor id rather than the <section>, so a jump from
        the index rail lands on the title with the section's own `scroll-margin`
        clearing the sticky nav.
      */}
      <h2 className={styles.title} id={id}>
        {title}
      </h2>
      <p className={styles.count}>{count}</p>
      <p className={styles.note}>{children}</p>
    </header>
  );
}
