// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// layouts/class_section_tabs.dart.
//
// `ClassFormat.sectionTabs` — photo and meta stay put, the three sections share
// one SWIPEABLE pane. Takes the scroll out of the decision: what the class is
// and when it runs is always on screen. The cost is that two thirds of the
// detail now sits behind a tap.
//
// THE PANE IS AN INDEXED STACK, NOT A PAGER, and that is the load-bearing
// detail of the whole arrangement. The Dart spells out why: "a PageView never
// builds the pages you have not visited, which would take two of this screen's
// sections out of the tree entirely. Hiding a section behind a tab is an
// ARRANGEMENT; dropping it is a different screen." The web equivalent is that
// all three panes are always RENDERED and the inactive two are hidden with the
// `hidden` attribute — never conditionally unmounted. ../../__tests__/
// classFormats.test.tsx counts through the whole container for exactly that
// reason, so a pane that vanished when unselected would fail the count.
//
// NO STATE-IN-EFFECT. The selected index is plain `useState` written only from
// the tab click and the swipe — both event handlers. The React Compiler rules
// are fatal in this package and `set-state-in-effect` is one of them
// (../../../../CLAUDE.md), so there is deliberately no effect here at all.

import { useRef, useState } from 'react';
import type { PointerEvent as ReactPointerEvent } from 'react';

import { ClassScreenTopbar } from '../parts/ClassScreenTopbar';
import { ClassTabBar } from '../parts/ClassTabBar';
import { ClassDetailsSection } from '../sections/ClassDetailsSection';
import { ClassImageBanner } from '../sections/ClassImageBanner';
import { ClassInstructorSection } from '../sections/ClassInstructorSection';
import { ClassLocationSection } from '../sections/ClassLocationSection';
import { ClassMetaSection } from '../sections/ClassMetaSection';
import { ClassReserveFooter } from '../sections/ClassReserveFooter';

import type { ClassLayoutProps } from './layoutProps';
import styles from './layouts.module.css';

/** `_kTabs`. */
const TABS: readonly string[] = Object.freeze(['Details', 'Instructor', 'Location']);

/**
 * `_kSwipeVelocity` 50 — the flick speed that turns a drag into a tab change.
 * Matches the screen's own swipe threshold in the Dart so the two read as one
 * gesture family. Flutter's `primaryVelocity` is logical px per SECOND, which
 * is what the pointer maths below reproduces.
 */
const SWIPE_VELOCITY = 50;

export function ClassSectionTabs({ detail, gymName, gymLogoSrc }: ClassLayoutProps) {
  const cls = detail.classData;
  const [index, setIndex] = useState(0);
  // Written only inside pointer handlers — never during render, which the
  // compiler's `refs` rule makes an error.
  const drag = useRef<{ x: number; t: number } | null>(null);

  function select(next: number) {
    setIndex(Math.min(Math.max(next, 0), TABS.length - 1));
  }

  function onPointerDown(event: ReactPointerEvent<HTMLDivElement>) {
    drag.current = { x: event.clientX, t: event.timeStamp };
  }

  function onPointerUp(event: ReactPointerEvent<HTMLDivElement>) {
    const start = drag.current;
    drag.current = null;
    if (start === null) return;
    const dt = event.timeStamp - start.t;
    if (dt <= 0) return;
    // `details.primaryVelocity` — px/s, negative when travelling left.
    const velocity = ((event.clientX - start.x) / dt) * 1000;
    if (velocity < -SWIPE_VELOCITY) select(index + 1);
    if (velocity > SWIPE_VELOCITY) select(index - 1);
  }

  const panes = [
    <ClassDetailsSection key="details" description={cls.description} />,
    <ClassInstructorSection
      key="instructor"
      bio={cls.instructorBio}
      imageUrl={cls.instructorImageUrl}
      layout="avatarTop"
    />,
    <ClassLocationSection key="location" address={detail.address} mapSrc={detail.mapSrc} />,
  ];

  return (
    <div className={styles.column}>
      <ClassScreenTopbar gymName={gymName} gymLogoSrc={gymLogoSrc} />
      <ClassImageBanner imageUrl={cls.imageUrl} treatment="compact" />
      <div className={styles.tabsMeta}>
        <ClassMetaSection detail={detail} />
      </div>
      <ClassTabBar labels={TABS} index={index} onSelect={select} />
      {/*
        The pane's own horizontal drag. `HitTestBehavior.translucent` on the
        Dart; here the handlers sit on the wrapper and `touch-action: pan-y`
        leaves the vertical scroll to the browser while claiming the horizontal.
      */}
      <div
        className={styles.paneHost}
        onPointerDown={onPointerDown}
        onPointerUp={onPointerUp}
        data-class-swipe="tabs"
      >
        {panes.map((pane, i) => (
          <div
            key={TABS[i]}
            className={styles.pane}
            hidden={i !== index}
            role="tabpanel"
          >
            {pane}
          </div>
        ))}
      </div>
      <ClassReserveFooter />
    </div>
  );
}
