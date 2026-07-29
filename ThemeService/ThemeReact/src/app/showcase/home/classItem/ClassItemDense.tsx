// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// class_item/layouts/class_item_dense.dart.
//
// `ClassItemLayout.dense` — the compact row. Small square thumbnail leading,
// tight meta, hairline rule. Fits the most classes under a hero without the
// list turning into a wall.
//
// The docs' `nextUpHero` sketch drops the thumbnail here. IT STAYS: dropping it
// would remove an element from the screen, which is the one thing a layout
// format may never do, and ../__tests__/homeFormats.test.tsx is the gate.

import { ClassItemMeta } from './ClassItemMeta';
import { ClassItemRule } from './ClassItemRule';
import { ClassItemThumb } from './ClassItemThumb';
import styles from './ClassItemDense.module.css';
import type { ClassItemTreatmentProps } from './ClassItemTextLeft';

export function ClassItemDense({ classData, showBookings }: ClassItemTreatmentProps) {
  return (
    <div className={styles.item}>
      <div className={styles.row}>
        <ClassItemThumb
          classData={classData}
          className={styles.photo}
          imgClassName={styles.photoImg}
        />
        <ClassItemMeta
          classData={classData}
          showBookings={showBookings}
          className={styles.info}
        />
      </div>
      <ClassItemRule hairline />
    </div>
  );
}
