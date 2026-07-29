// Ports ../../../../../CRM/lib/shared/widgets/phone_frame.dart.
//
// A realistic phone mockup that wraps `children` in a device body — rounded
// titanium frame, thin bezel, and a dynamic-island pill — scaled to fit.
//
// The geometry constants below are PHYSICAL DEVICE MEASUREMENTS (a real phone's
// body radius, bezel, dynamic island), not fungible design tokens, which is why
// the Dart file keeps them as private consts and why they are repeated here
// rather than pushed into ../tokens/adminTokens.ts.
//
// The child renders at the real screen size (390×844), so member-app-sized
// content measures exactly as it would on a device. Dart gets that from
// `AspectRatio` + `FittedBox(fit: BoxFit.contain)` around a fixed `SizedBox`.
//
// WHY THE CONTAIN FIT IS COMPUTED IN JS, not `aspect-ratio` + `max-height`:
// CSS re-derives the other axis from a ratio only when the size it is deriving
// FROM is the definite one. A box with `width: 100%` and `aspect-ratio` in a
// SHORT container computes a huge height, and `max-height: 100%` then merely
// clips it — the width does not shrink to keep the ratio, so the phone spills
// out of a viewport-height pane. `min(w/418, h/872)` is `BoxFit.contain`
// exactly, and `transform: scale()` is the one CSS primitive that scales
// laid-out pixels rather than re-laying them out, which is what `FittedBox`
// does.
//
// Dart also overrides the child's `MediaQuery` with a `padding.top` status
// inset so content clears the island. The web has no MediaQuery to override, so
// the inset is published as a CSS variable (`--phone-status-inset`) on the
// screen element and inherited by whatever renders inside it.

import type { CSSProperties, ReactNode } from 'react';

import styles from './PhoneFrame.module.css';
import { useElementSize } from './useElementSize';

// Device geometry (logical px at 1x).
const SCREEN_W = 390;
const SCREEN_H = 844;
const BEZEL = 14;
const BODY_RADIUS = 66;
const SCREEN_RADIUS = 52;
const STATUS_INSET = 52; // room below the dynamic island
const ISLAND_W = 122;
const ISLAND_H = 34;
const ISLAND_TOP_GAP = 11;

const BODY_W = SCREEN_W + BEZEL * 2;
const BODY_H = SCREEN_H + BEZEL * 2;

export interface PhoneFrameProps {
  children: ReactNode;
}

export function PhoneFrame({ children }: PhoneFrameProps) {
  const [measureRef, { width, height }] = useElementSize<HTMLDivElement>();
  // `BoxFit.contain`: whichever axis binds first.
  const scale =
    width === 0 || height === 0 ? 0 : Math.min(width / BODY_W, height / BODY_H);
  const bodyStyle: CSSProperties = {
    width: `${BODY_W}px`,
    height: `${BODY_H}px`,
    borderRadius: `${BODY_RADIUS}px`,
    transform: `translate(-50%, -50%) scale(${scale})`,
  };
  return (
    <div ref={measureRef} className={styles.fit}>
      <div className={styles.body} style={bodyStyle}>
        <div
          className={styles.screen}
          style={{
            left: `${BEZEL}px`,
            top: `${BEZEL}px`,
            width: `${SCREEN_W}px`,
            height: `${SCREEN_H}px`,
            borderRadius: `${SCREEN_RADIUS}px`,
            ['--phone-status-inset' as string]: `${STATUS_INSET}px`,
          }}
        >
          {children}
        </div>
        <div
          className={styles.island}
          style={{
            top: `${BEZEL + ISLAND_TOP_GAP}px`,
            width: `${ISLAND_W}px`,
            height: `${ISLAND_H}px`,
            borderRadius: `${ISLAND_H / 2}px`,
          }}
        />
      </div>
    </div>
  );
}
