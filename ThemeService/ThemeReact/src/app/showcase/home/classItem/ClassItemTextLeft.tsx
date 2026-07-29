// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// class_item/layouts/class_item_text_left.dart.
//
// `ClassItemLayout.textLeftThumbRight` — THE ROW THAT SHIPS TODAY.
//
// Meta column left, small 16:9 thumbnail right, rule beneath. Element for
// element the previous flat ./../ClassListItem.tsx rendering, so a tenant with
// no `home_format` slot sees no change — ../__tests__/agendaListBaseline.html
// is the fixture that keeps that true.

import type { ShowcaseClass } from '../homeClass';

import { ClassItemMeta } from './ClassItemMeta';
import { ClassItemRule } from './ClassItemRule';
import { ClassItemThumb } from './ClassItemThumb';
import styles from './ClassItemTextLeft.module.css';

export interface ClassItemTreatmentProps {
  classData: ShowcaseClass;
  showBookings: boolean;
}

export function ClassItemTextLeft({ classData, showBookings }: ClassItemTreatmentProps) {
  return (
    <div className={styles.item}>
      <div className={styles.row}>
        <ClassItemMeta
          classData={classData}
          showBookings={showBookings}
          className={styles.info}
        />
        <ClassItemThumb
          classData={classData}
          className={styles.photo}
          imgClassName={styles.photoImg}
        />
      </div>
      <ClassItemRule />
    </div>
  );
}
