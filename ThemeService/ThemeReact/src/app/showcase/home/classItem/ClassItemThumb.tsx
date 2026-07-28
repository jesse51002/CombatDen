// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// class_item/class_item_thumb.dart.
//
// The class image. EVERY treatment renders exactly one of these — the size and
// the crop move, the image never leaves. Dart takes width / height /
// aspectRatio / borderRadius as arguments; the CSS equivalent of those four is
// a class, so the frame box and the `<img>` box are both handed in by the
// treatment and this component owns only what Dart's `Image` owns: the source
// ladder and the error fallback.
//
// The photo is the injected gym URL when the host supplied one, else the
// bundled sample (`ShowcaseAsset.imageOrNetwork`). A network photo that fails
// to load degrades to the flat `card` rectangle the frame paints, rather than a
// broken-image box — Dart's `errorBuilder`.

import { useState } from 'react';

import { showcaseAssetOrNetwork } from '../../showcaseAssets';
import type { ShowcaseClass } from '../homeClass';

export interface ClassItemThumbProps {
  classData: ShowcaseClass;
  /**
   * The frame: size, crop, radius, and the `card` colour behind a dead URL.
   *
   * `string | undefined` rather than `string` because a CSS-module lookup is
   * exactly that under this package's `noUncheckedIndexedAccess` — the prop is
   * still REQUIRED, so a treatment cannot forget to size its own thumbnail.
   */
  className: string | undefined;
  /** The `<img>` itself — `object-fit: cover` at the frame's size. */
  imgClassName: string | undefined;
}

export function ClassItemThumb({ classData, className, imgClassName }: ClassItemThumbProps) {
  const src = showcaseAssetOrNetwork(
    classData.imageUrl,
    classData.imageAsset ?? 'class_photo_1.png',
  );
  // `key` remounts the frame whenever the photo changes — a theme switch swaps
  // the whole class list, and without the reset one dead URL would pin this
  // slot to the empty box forever. The same trick <ThemedImage> uses, and for
  // the same reason: resetting in an effect is a lint error in this package.
  return <ClassItemThumbFrame key={src} src={src} className={className} imgClassName={imgClassName} />;
}

interface FrameProps {
  src: string;
  className: string | undefined;
  imgClassName: string | undefined;
}

function ClassItemThumbFrame({ src, className, imgClassName }: FrameProps) {
  const [failed, setFailed] = useState(false);
  return (
    <div className={className}>
      {!failed && (
        <img
          src={src}
          alt=""
          className={imgClassName}
          onError={() => {
            setFailed(true);
          }}
        />
      )}
    </div>
  );
}
