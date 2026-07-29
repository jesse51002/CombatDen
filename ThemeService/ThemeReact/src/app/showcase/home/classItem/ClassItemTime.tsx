// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// class_item/class_item_time.dart.
//
// When the class runs. Its own component because the `spine` treatment hoists
// the time out of the meta column into a leading gutter. MOVING one component
// keeps the time rendered exactly once; re-typing the text in the gutter would
// render it twice, which is an added element, not an arrangement.

import styles from './ClassItemTime.module.css';
import type { ShowcaseClass } from '../homeClass';

export interface ClassItemTimeProps {
  classData: ShowcaseClass;
  /** Gutter form: start time over the duration, two short lines. */
  stacked?: boolean;
}

export function ClassItemTime({ classData, stacked = false }: ClassItemTimeProps) {
  if (!stacked) {
    return (
      // `meta` keeps the class name the shipped row used, so the agendaList
      // baseline in ./__tests__/agendaListBaseline.html stays byte-identical.
      <span className={styles.meta}>
        {classData.timeRange} ({String(classData.durationMinutes)} min)
      </span>
    );
  }
  // `timeRange.split(' - ').first` — the start time alone.
  const [start = classData.timeRange] = classData.timeRange.split(' - ');
  return (
    <div className={styles.stacked}>
      <span className={styles.start}>{start}</span>
      <span className={styles.duration}>{String(classData.durationMinutes)} min</span>
    </div>
  );
}
