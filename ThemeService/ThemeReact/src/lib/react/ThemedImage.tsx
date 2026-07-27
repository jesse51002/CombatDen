// Ports ../../ThemeFlutter/lib/theme/fallback_image_provider.dart, and with it
// the render half of theme_image.dart.
//
// The Dart file is 120 lines of `ImageStreamCompleter` relay because
// `ImageProvider.resolve` is `@nonVirtual` and composing two providers has to be
// done by hand. The browser hands the same behaviour over in one `onError`:
// what actually ports is the CONTRACT, not the machinery.
//
// The contract: a theme is a BEST-EFFORT live override. A bad override asset
// must never surface as a broken image box — it degrades to the caller's
// bundled asset, exactly as an absent slot already does.

import type { ImgHTMLAttributes } from 'react';
import { useState } from 'react';

import { useThemeImageSrc } from './hooks';

export interface ThemedImageProps extends Omit<ImgHTMLAttributes<HTMLImageElement>, 'src'> {
  /** The image slot id to resolve. */
  slot: string;
  /**
   * The caller's own bundled asset, drawn when the slot is absent AND when the
   * resolved override fails to load.
   *
   * The runtime deliberately owns no fallback of its own: white-label tenants
   * keep their default assets in their own build, which is what makes the theme
   * a pure live override and the app resilient with zero backend.
   */
  fallbackSrc: string;
}

export function ThemedImage({ slot, fallbackSrc, ...imgProps }: ThemedImageProps) {
  const resolved = useThemeImageSrc(slot, fallbackSrc);
  // `key` remounts the frame whenever the resolved URL changes — on a theme
  // switch, on a re-fetch that moved the asset's `?v=` hash. That reset is what
  // Dart gets for free by building a new provider: without it, one theme's 404
  // would pin every LATER theme to the bundled fallback.
  //
  // (ThemeFlutter's own comment would call this an effect; a synchronous
  // setState inside an effect is what `react-hooks/set-state-in-effect` — an
  // error in this package's lint gate — exists to stop. Remounting is the same
  // reset with none of the extra render pass.)
  return <ThemedImageFrame key={resolved} src={resolved} fallbackSrc={fallbackSrc} {...imgProps} />;
}

interface ThemedImageFrameProps extends Omit<ImgHTMLAttributes<HTMLImageElement>, 'src'> {
  src: string;
  fallbackSrc: string;
}

function ThemedImageFrame({ src, fallbackSrc, onError, ...imgProps }: ThemedImageFrameProps) {
  const [failed, setFailed] = useState(false);
  return (
    <img
      {...imgProps}
      src={failed ? fallbackSrc : src}
      onError={(event) => {
        // The bundled fallback failing too is a real build bug: let it through
        // to the caller's own handler rather than looping on setState.
        if (!failed) setFailed(true);
        onError?.(event);
      }}
    />
  );
}
