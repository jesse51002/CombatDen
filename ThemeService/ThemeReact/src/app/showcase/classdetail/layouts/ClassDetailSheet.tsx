// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// layouts/class_detail_sheet.dart.
//
// `ClassFormat.detailSheet` — the photo is a FIXED BACKDROP and the content
// rises over it as a draggable sheet. The reserve action sits at the TOP of the
// sheet: in thumb reach on the way down, rather than at the end of a scroll.
//
// HAND-BUILT, exactly as the Dart is. Flutter reaches for `AnimatedPositioned`
// + a drag strip rather than `DraggableScrollableSheet`; here it is a `top`
// percentage with a CSS transition, driven by pointer events on the grab strip
// only (../parts/ClassSheetSurface.tsx explains why the strip owns the drag).
//
// THE SNAP CURVE IS `Curves.easeOut` = `Cubic(0.0, 0.0, 0.58, 1.0)`, written
// straight into `cubic-bezier()`. CSS needs none of ../../celebrations/curves.ts
// here: `cubic-bezier()` IS the same curve, which is the whole reason that
// bisection exists only for values JS has to compute per frame
// (../../../../CLAUDE.md).
//
// NO STATE-IN-EFFECT: the sheet's position is plain `useState` written only
// from pointer handlers.

import { useRef, useState } from 'react';
import type { PointerEvent as ReactPointerEvent } from 'react';

import { ClassHeroScrim } from '../parts/ClassHeroScrim';
import { ClassScreenTopbar } from '../parts/ClassScreenTopbar';
import { ClassSheetSurface } from '../parts/ClassSheetSurface';
import { ClassImageBanner } from '../sections/ClassImageBanner';

import type { ClassLayoutProps } from './layoutProps';
import styles from './layouts.module.css';

/** Where the sheet's top edge sits, as a fraction of the body height. */
const OPEN_TOP = 0.1;
const REST_TOP = 0.44;

export function ClassDetailSheet({ detail, gymName, gymLogoSrc }: ClassLayoutProps) {
  const cls = detail.classData;
  const [top, setTop] = useState(REST_TOP);
  const [dragging, setDragging] = useState(false);
  const host = useRef<HTMLDivElement | null>(null);
  // Written only inside pointer handlers, never during render.
  const drag = useRef<{ y: number; top: number } | null>(null);

  function bodyHeight(): number {
    return host.current?.getBoundingClientRect().height ?? 0;
  }

  function onPointerDown(event: ReactPointerEvent<HTMLElement>) {
    drag.current = { y: event.clientY, top };
    setDragging(true);
    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function onPointerMove(event: ReactPointerEvent<HTMLDivElement>) {
    const start = drag.current;
    const height = bodyHeight();
    if (start === null || height <= 0) return;
    // `_top + details.delta.dy / height`, clamped to the two stops.
    const next = start.top + (event.clientY - start.y) / height;
    setTop(Math.min(Math.max(next, OPEN_TOP), REST_TOP));
  }

  function onPointerUp(event: ReactPointerEvent<HTMLDivElement>) {
    const start = drag.current;
    drag.current = null;
    if (start === null) return;
    setDragging(false);
    // `_onDragEnd`: a flick decides by direction, a slow release by midpoint.
    const travel = event.clientY - start.y;
    const open = travel === 0 ? top < (OPEN_TOP + REST_TOP) / 2 : travel < 0;
    setTop(open ? OPEN_TOP : REST_TOP);
  }

  return (
    <div
      ref={host}
      className={styles.sheetHost}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
    >
      {/* `Positioned.fill(ClassKeyedBanner(treatment: backdrop))`. */}
      <div className={styles.backdrop}>
        <ClassImageBanner imageUrl={cls.imageUrl} treatment="backdrop" />
      </div>
      <ClassHeroScrim />
      <div className={styles.sheetTopbar}>
        <ClassScreenTopbar gymName={gymName} gymLogoSrc={gymLogoSrc} />
      </div>
      {/* `AnimatedPositioned(duration: _dragging ? zero : 220ms, easeOut)`. */}
      <div
        className={styles.sheet}
        style={{
          top: `${String(top * 100)}%`,
          transition: dragging ? 'none' : 'top 220ms cubic-bezier(0, 0, 0.58, 1)',
        }}
      >
        <ClassSheetSurface detail={detail} onHandlePointerDown={onPointerDown} />
      </div>
    </div>
  );
}
