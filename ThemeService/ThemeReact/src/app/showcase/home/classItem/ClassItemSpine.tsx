// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// class_item/layouts/class_item_spine.dart.
//
// `ClassItemLayout.spine` — the class hangs off its own start time.
//
// The time MOVES out of the meta column into a leading gutter (`showTime`
// false + a stacked <ClassItemTime>, so it is still rendered exactly once), and
// a vertical rule runs the full height of every row so consecutive classes read
// as one continuous timetable. The thumbnail demotes to a small square so the
// time column keeps the eye.

import { ClassItemMeta } from './ClassItemMeta';
import { ClassItemThumb } from './ClassItemThumb';
import { ClassItemTime } from './ClassItemTime';
import styles from './ClassItemSpine.module.css';
import type { ClassItemTreatmentProps } from './ClassItemTextLeft';

export function ClassItemSpine({ classData, showBookings }: ClassItemTreatmentProps) {
  return (
    <div className={styles.item}>
      <div className={styles.gutter}>
        <ClassItemTime classData={classData} stacked />
      </div>
      <div className={styles.rule} />
      <ClassItemMeta
        classData={classData}
        showBookings={showBookings}
        className={styles.info}
        showTime={false}
      />
      <ClassItemThumb
        classData={classData}
        className={styles.photo}
        imgClassName={styles.photoImg}
      />
    </div>
  );
}
