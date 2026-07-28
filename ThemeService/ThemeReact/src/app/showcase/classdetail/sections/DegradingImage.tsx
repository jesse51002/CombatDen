// Ports the `errorBuilder` every image on the class detail screen carries —
// `class_image_banner.dart:57`, `class_instructor_section.dart:110` — which
// paints a flat `card`-coloured box in the image's own shape rather than a
// broken-image glyph.
//
// It matters more here than anywhere else in the island: the class photo, the
// coach headshot and the map are the only NETWORK images on any showcase
// screen (every other one is a bundled PNG behind a theme slot), and the demo
// content points at third-party hosts. One dead URL must degrade to a shape,
// never to a browser placeholder that gives away the mock.
//
// The reset is a `key` REMOUNT, not an effect — the same trick
// ../../home/ClassListItem.tsx uses and for the same reason: `setState` in an
// effect to clear derived state is a React Compiler error in this package
// (../../../../CLAUDE.md). Without the reset, one dead URL would pin the box
// empty for every later theme, because the failure flag would outlive the src
// that caused it.

import { useState } from 'react';

export interface DegradingImageProps {
  src: string;
  className?: string | undefined;
  /** Applied to the wrapper that paints the fallback block. */
  frameClassName?: string | undefined;
  /**
   * Stamped on the frame — the element marker its owner is counted by
   * (../classParts.ts). On the FRAME rather than the `<img>` so the count
   * holds even when the image has degraded and the `<img>` is gone.
   */
  frameProps?: Record<string, string> | undefined;
}

export function DegradingImage({ src, ...rest }: DegradingImageProps) {
  return <ImageFrame key={src} src={src} {...rest} />;
}

function ImageFrame({ src, className, frameClassName, frameProps }: DegradingImageProps) {
  const [failed, setFailed] = useState(false);
  // An empty src never even attempts a request, so it starts failed rather than
  // firing `onError` — `fallbackClass.imageUrl` is `''` by design.
  const broken = failed || src === '';
  return (
    <div className={frameClassName} {...frameProps}>
      {!broken && (
        <img
          src={src}
          alt=""
          className={className}
          onError={() => {
            setFailed(true);
          }}
        />
      )}
    </div>
  );
}
