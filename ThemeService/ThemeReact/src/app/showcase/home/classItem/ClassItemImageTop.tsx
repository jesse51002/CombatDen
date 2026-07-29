// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// class_item/layouts/class_item_image_top.dart.
//
// `ClassItemLayout.imageTop` — a wide media card. The image leads at full
// column width, meta reads beneath it. Costs the most vertical space per class,
// which is why it is paired with `dayPager`, where only one day is on screen at
// a time.

import { ClassItemMeta } from './ClassItemMeta';
import { ClassItemThumb } from './ClassItemThumb';
import styles from './ClassItemImageTop.module.css';
import type { ClassItemTreatmentProps } from './ClassItemTextLeft';

export function ClassItemImageTop({ classData, showBookings }: ClassItemTreatmentProps) {
  return (
    <div className={styles.item}>
      <ClassItemThumb
        classData={classData}
        className={styles.photo}
        imgClassName={styles.photoImg}
      />
      <ClassItemMeta classData={classData} showBookings={showBookings} className={styles.info} />
    </div>
  );
}
