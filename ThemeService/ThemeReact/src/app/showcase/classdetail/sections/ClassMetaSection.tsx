// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// widgets/{class_meta_section,class_meta_spec_table,class_attending_row}.dart —
// the class title and its location / date / time / attending block.
//
// EVERY VALUE RENDERS THE SAME FACTS. Only their shape and their surface
// change: stacked on the page (ships), the same block on the photo behind a
// scrim, or a label/value table beside an inline photo thumb.
//
// THE THREE DART FILES ARE ONE FILE HERE. `ClassAttendingRow` is its own widget
// on the Dart side because BOTH meta treatments carry it and the icon "must not
// quietly disappear from one of them" — that guarantee is about there being ONE
// definition with two call sites, which is exactly what it still has here, now
// that both call sites live beside it. Splitting it into a third file would buy
// a filename, not the guarantee.

import type { ReactNode } from 'react';

import { PersonIcon } from '../../support/icons';
import { cx } from '../../cx';
import { CLASS_PART, classPart } from '../classParts';
import type { ClassDetail } from '../classDetail';

import styles from './ClassMetaSection.module.css';

/** `ClassMetaLayout`. */
export type ClassMetaLayout = 'stacked' | 'overlay' | 'specTable';

export interface ClassMetaSectionProps {
  detail: ClassDetail;
  /** Defaults to `stacked`, the arrangement that ships. */
  layout?: ClassMetaLayout;
  /**
   * Presentation slot used by `specTable` ONLY: the class photo, inline with
   * the title instead of above the block. Nothing else is ever passed to it.
   */
  leading?: ReactNode;
}

export function ClassMetaSection({ detail, layout = 'stacked', leading }: ClassMetaSectionProps) {
  if (layout === 'specTable') return <ClassMetaSpecTable detail={detail} leading={leading} />;
  return (
    <div
      className={cx(styles.meta, layout === 'overlay' && styles.overlay)}
      {...classPart(CLASS_PART.meta)}
    >
      <StackedMeta detail={detail} />
    </div>
  );
}

/** `_StackedMeta` — `Column(start, spacing: spacingMedium)`. */
function StackedMeta({ detail }: { detail: ClassDetail }) {
  const cls = detail.classData;
  return (
    <div className={styles.stacked}>
      <h1 className={styles.title}>{cls.name}</h1>
      {/* `_SpecificsBlock` — `Column(start, spacing: spacingTiny)`. */}
      <div className={styles.specifics}>
        <span className={styles.metaText}>{detail.location}</span>
        <span className={styles.metaText}>
          {detail.dateLabel} ‧ {cls.timeRange}
        </span>
        {cls.attending !== undefined && <ClassAttendingRow count={cls.attending} />}
      </div>
    </div>
  );
}

/**
 * `ClassMetaSpecTable` — the `specBrief` treatment: the title beside an inline
 * photo thumb, then the same facts as a dense label/value table.
 */
function ClassMetaSpecTable({
  detail,
  leading,
}: {
  detail: ClassDetail;
  leading?: ReactNode;
}) {
  const cls = detail.classData;
  return (
    <div className={styles.specTable} {...classPart(CLASS_PART.meta)}>
      <div className={styles.specHead}>
        {leading}
        <h1 className={cx(styles.title, styles.specTitle)}>{cls.name}</h1>
      </div>
      <div className={styles.specRows}>
        <SpecRow label="Location">
          <span className={styles.specValue}>{detail.location}</span>
        </SpecRow>
        <SpecRow label="Date">
          <span className={styles.specValue}>{detail.dateLabel}</span>
        </SpecRow>
        <SpecRow label="Time">
          <span className={styles.specValue}>{cls.timeRange}</span>
        </SpecRow>
        {cls.attending !== undefined && (
          <SpecRow label="Attending">
            <ClassAttendingRow count={cls.attending} />
          </SpecRow>
        )}
      </div>
    </div>
  );
}

/** `_SpecRow` — a fixed `_kLabelWidth` 96 label so the values line up. */
function SpecRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className={styles.specRow}>
      <span className={styles.specLabel}>{label}</span>
      <div className={styles.specCell}>{children}</div>
    </div>
  );
}

/** `ClassAttendingRow` — "N attending" with its person icon. */
function ClassAttendingRow({ count }: { count: number }) {
  return (
    <span className={styles.attending}>
      <PersonIcon size={20} className={styles.attendingIcon} />
      {String(count)} attending
    </span>
  );
}
