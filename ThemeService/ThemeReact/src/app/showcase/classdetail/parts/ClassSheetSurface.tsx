// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// layouts/parts/class_sheet_surface.dart — the `detailSheet` sheet: the reserve
// action at the TOP, then the same sections the other arrangements scroll
// through.
//
// THE GRAB STRIP IS THE DRAG TARGET, and that is load-bearing rather than
// decorative: a drag on the CONTENT scrolls it and a drag on the STRIP resizes
// the sheet, so the two gestures never fight over the same pointer. Handing the
// whole surface the drag would make the section list unscrollable.

import type { PointerEvent as ReactPointerEvent } from 'react';

import type { ClassDetail } from '../classDetail';
import { ClassDetailsSection } from '../sections/ClassDetailsSection';
import { ClassInstructorSection } from '../sections/ClassInstructorSection';
import { ClassLocationSection } from '../sections/ClassLocationSection';
import { ClassMetaSection } from '../sections/ClassMetaSection';
import { ClassReserveFooter } from '../sections/ClassReserveFooter';

import { ClassSectionStack } from './ClassSectionStack';
import styles from './ClassSheetSurface.module.css';

export interface ClassSheetSurfaceProps {
  detail: ClassDetail;
  onHandlePointerDown: (event: ReactPointerEvent<HTMLElement>) => void;
}

export function ClassSheetSurface({ detail, onHandlePointerDown }: ClassSheetSurfaceProps) {
  const cls = detail.classData;
  return (
    <div className={styles.sheet}>
      {/* `_GrabHandle` inside its own drag GestureDetector. */}
      <div
        className={styles.handleTarget}
        onPointerDown={onHandlePointerDown}
        role="separator"
        aria-label="Resize details"
      >
        <div className={styles.handle} />
      </div>
      <ClassReserveFooter position="sheetTop" />
      <div className={styles.body}>
        <ClassSectionStack
          sections={[
            <ClassMetaSection key="meta" detail={detail} />,
            <ClassDetailsSection key="details" description={cls.description} />,
            <ClassInstructorSection
              key="instructor"
              bio={cls.instructorBio}
              imageUrl={cls.instructorImageUrl}
            />,
            <ClassLocationSection
              key="location"
              address={detail.address}
              mapSrc={detail.mapSrc}
            />,
          ]}
        />
      </div>
    </div>
  );
}
