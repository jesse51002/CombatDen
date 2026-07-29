// Ports ../../../../../../CRM/lib/showcase/home/day_class_group.dart — a clone
// of MobileApp's `DayClassGroup`: an upper-cased day label over its class rows
// — plus, for the two arrangements beneath it, MobileApp's own
// `.../class_schedule/day_class_group.dart` and its `day_group/` pair.
//
// EVERY home format renders these: the band and the classes ARE the day, not a
// variant. `itemLayout` and `grid` pick only how the classes are arranged
// beneath the band.
//
// Dart splits the two arrangements into `DayGroupList` / `DayGroupGrid` because
// each is a widget with its own spacing and padding. Here each is a single CSS
// rule over the same `<ClassListItem>` children, so they stay in this file —
// two elements rather than two components. The stack case deliberately renders
// the rows as DIRECT children of `.group`, exactly as the shipped board did:
// `.group`'s own `spacing: spacingLarge` is already Dart's `DayGroupList`
// spacing, so wrapping them would have changed the element tree for no gain.

import { ClassListItem } from './ClassListItem';
import type { ClassItemLayout } from './classItem/classItemLayout';
import styles from './DayClassGroup.module.css';
import type { ShowcaseClass, ShowcaseDay } from './homeClass';

export interface DayClassGroupProps {
  day: ShowcaseDay;
  showBookings?: boolean;
  /** How each row is drawn. Ignored when `grid` — the grid owns its cell. */
  itemLayout?: ClassItemLayout;
  /** Two-up cards instead of a stack. */
  grid?: boolean;
}

export function DayClassGroup({
  day,
  showBookings = true,
  itemLayout = 'textLeftThumbRight',
  grid = false,
}: DayClassGroupProps) {
  const rows = day.classes.map((classData, i) => (
    <ClassListItem
      // The schedule is a fixed four-slot list, so the slot index IS the row's
      // identity; two days can legitimately carry the same class name.
      key={rowKey(i, classData)}
      classData={classData}
      showBookings={showBookings}
      layout={grid ? 'card' : itemLayout}
    />
  ));
  return (
    <section className={styles.group}>
      <h2 className={styles.label}>{day.label.toUpperCase()}</h2>
      {grid ? <div className={styles.grid}>{rows}</div> : rows}
    </section>
  );
}

function rowKey(index: number, classData: ShowcaseClass): string {
  return `${String(index)}-${classData.name}`;
}
