// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// class_item/class_item_meta.dart.
//
// The text column of a class row: title, time, instructor, attendee count and
// the booked mark. IDENTICAL IN EVERY TREATMENT — that is the point of pulling
// it out. A treatment may re-place this column and re-scale its gaps; it may
// not drop a line from it.
//
// ONE DELIBERATE SHAPE DIFFERENCE FROM THE DART. Flutter's `tight` flag picks
// the Column's own `spacing`; here the COLUMN BOX ITSELF (flex sizing and the
// gap) belongs to the treatment's stylesheet, which is what lets the shipped
// `textLeftThumbRight` row keep the exact `class="info"` element the baseline
// fixture pins. So there is no `tight` prop: `dense` / `spine` / `card` write
// the tighter gap in their own `.module.css`, and the flag has no other effect
// in the Dart either.

import { CheckIcon, PersonIcon } from '../../support/icons';
import type { ShowcaseClass } from '../homeClass';

import { ClassItemTime } from './ClassItemTime';
import styles from './ClassItemMeta.module.css';

export interface ClassItemMetaProps {
  classData: ShowcaseClass;
  showBookings: boolean;
  /**
   * The column box — flex sizing and the inter-line gap. The treatment's.
   *
   * `string | undefined` rather than `string` because a CSS-module lookup is
   * exactly that under this package's `noUncheckedIndexedAccess`. The prop is
   * still REQUIRED: a treatment cannot forget to lay out its own meta column.
   */
  className: string | undefined;
  /**
   * False only where the treatment hoists <ClassItemTime> into its own gutter
   * (the spine). The time MOVES; it is never dropped.
   */
  showTime?: boolean;
}

export function ClassItemMeta({
  classData,
  showBookings,
  className,
  showTime = true,
}: ClassItemMetaProps) {
  return (
    <div className={className}>
      <span className={styles.name}>{classData.name}</span>
      {showTime && <ClassItemTime classData={classData} />}
      <span className={styles.mentor}>{classData.mentor}</span>
      {classData.attending !== undefined && <BookedCount count={classData.attending} />}
      {showBookings && classData.isBooked && <BookedConfirmation />}
    </div>
  );
}

/** `_BookedMark`. */
function BookedConfirmation() {
  return (
    <span className={styles.booked}>
      <CheckIcon size={16} className={styles.bookedIcon} />
      You booked this class!
    </span>
  );
}

/** `_Attendees`. */
function BookedCount({ count }: { count: number }) {
  return (
    <span className={styles.attending}>
      <PersonIcon size={16} className={styles.attendingIcon} />
      {String(count)} attending
    </span>
  );
}
