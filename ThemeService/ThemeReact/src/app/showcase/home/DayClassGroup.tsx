// Ports ../../../../../../CRM/lib/showcase/home/day_class_group.dart — a clone
// of MobileApp's `DayClassGroup`: an upper-cased day label over its class rows.

import { ClassListItem } from './ClassListItem';
import styles from './DayClassGroup.module.css';
import type { ShowcaseDay } from './homeClass';

export interface DayClassGroupProps {
  day: ShowcaseDay;
  showBookings?: boolean;
}

export function DayClassGroup({ day, showBookings = true }: DayClassGroupProps) {
  return (
    <section className={styles.group}>
      <h2 className={styles.label}>{day.label.toUpperCase()}</h2>
      {day.classes.map((classData, i) => (
        <ClassListItem
          // The schedule is a fixed four-slot list, so the slot index IS the
          // row's identity; two days can legitimately carry the same class name.
          key={`${String(i)}-${classData.name}`}
          classData={classData}
          showBookings={showBookings}
        />
      ))}
    </section>
  );
}
