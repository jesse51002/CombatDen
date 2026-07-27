// Ports ../../../../../../CRM/lib/showcase/home/class_list_item.dart — a clone
// of MobileApp's `ClassListItem`: one schedule row (name, time, mentor, the
// demo attending count and booked tick) with the class photo on the right, over
// a `divider` hairline. The tap is a preview no-op.
//
// The photo is the injected gym URL when the host supplied one, else the
// bundled sample (`ShowcaseAsset.imageOrNetwork`). A network photo that fails
// to load degrades to a flat `card` rectangle rather than a broken-image box —
// Dart's `errorBuilder`.

import { useState } from 'react';

import { showcaseAssetOrNetwork } from '../showcaseAssets';
import { CheckIcon, PersonIcon } from '../support/icons';

import styles from './ClassListItem.module.css';
import type { ShowcaseClass } from './homeClass';

export interface ClassListItemProps {
  classData: ShowcaseClass;
  showBookings?: boolean;
}

export function ClassListItem({ classData, showBookings = true }: ClassListItemProps) {
  return (
    <div className={styles.item}>
      <div className={styles.row}>
        <div className={styles.info}>
          <span className={styles.name}>{classData.name}</span>
          <span className={styles.meta}>
            {classData.timeRange} ({String(classData.durationMinutes)} min)
          </span>
          <span className={styles.mentor}>{classData.mentor}</span>
          {classData.attending !== undefined && <BookedCount count={classData.attending} />}
          {showBookings && classData.isBooked && <BookedConfirmation />}
        </div>
        <ClassPhoto classData={classData} />
      </div>
      <div className={styles.divider} />
    </div>
  );
}

function ClassPhoto({ classData }: { classData: ShowcaseClass }) {
  const src = showcaseAssetOrNetwork(
    classData.imageUrl,
    classData.imageAsset ?? 'class_photo_1.png',
  );
  // `key` remounts the frame whenever the photo changes — a theme switch swaps
  // the whole class list, and without the reset one dead URL would pin this
  // slot to the empty box forever. The same trick <ThemedImage> uses, and for
  // the same reason: resetting in an effect is a lint error in this package.
  return <ClassPhotoFrame key={src} src={src} />;
}

function ClassPhotoFrame({ src }: { src: string }) {
  const [failed, setFailed] = useState(false);
  return (
    <div className={styles.photo}>
      {!failed && (
        <img
          src={src}
          alt=""
          className={styles.photoImg}
          onError={() => {
            setFailed(true);
          }}
        />
      )}
    </div>
  );
}

/** `_BookedConfirmation`. */
function BookedConfirmation() {
  return (
    <span className={styles.booked}>
      <CheckIcon size={16} className={styles.bookedIcon} />
      You booked this class!
    </span>
  );
}

/** `_BookedCount`. */
function BookedCount({ count }: { count: number }) {
  return (
    <span className={styles.attending}>
      <PersonIcon size={16} className={styles.attendingIcon} />
      {String(count)} attending
    </span>
  );
}
