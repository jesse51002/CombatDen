// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// class_item/layouts/class_item_card.dart.
//
// `ClassItemLayout.card` — a grid cell. Raised surface, 4:3 image on top, meta
// padded beneath. Sized by the COLUMN it lands in rather than by the screen, so
// it is the only treatment that has to survive a half-width measure.

import { ClassItemMeta } from './ClassItemMeta';
import { ClassItemThumb } from './ClassItemThumb';
import styles from './ClassItemCard.module.css';
import type { ClassItemTreatmentProps } from './ClassItemTextLeft';

export function ClassItemCard({ classData, showBookings }: ClassItemTreatmentProps) {
  return (
    <div className={styles.card}>
      <ClassItemThumb
        classData={classData}
        className={styles.photo}
        imgClassName={styles.photoImg}
      />
      <div className={styles.body}>
        <ClassItemMeta
          classData={classData}
          showBookings={showBookings}
          className={styles.info}
        />
      </div>
    </div>
  );
}
