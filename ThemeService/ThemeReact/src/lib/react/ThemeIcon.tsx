// Ports ../../ThemeFlutter/lib/theme/theme_icon.dart.
//
// TINTING. Dart draws the tenant SVG through
// `ColorFilter.mode(tint, BlendMode.srcIn)` — "keep the source's alpha, replace
// its colour". The literal CSS equivalent is a MASK: the SVG becomes the alpha
// channel and a solid background colour shows through it. That is a pixel-exact
// match for `srcIn` on a monochrome icon, and — unlike inlining the SVG markup,
// the other way to recolour one — it needs no CORS headers and no fetch,
// because the browser treats the mask as an image.
//
// THE TRAP the mask brings with it: a 404'd mask does not fail loudly, it
// renders an EMPTY BOX. `<img>` gives you `onError`; a CSS mask gives you
// nothing. So the URL is probed with an off-DOM `Image()` first and the caller's
// fallback stays on screen until the probe succeeds — and forever if it fails.
// Dart gets this from `SvgPicture.network`'s `placeholderBuilder`.

import type { CSSProperties, ReactNode } from 'react';
import { useEffect, useState } from 'react';

import { toCss } from '../theme/color';
import { EngineTokens } from '../theme/engineTokens';

import { useThemeIconUrl, useThemeToken } from './hooks';

export interface ThemeIconProps {
  /** The icon slot id to resolve. */
  slot: string;
  /**
   * The caller's own bundled icon, rendered when the slot is absent, while the
   * override is probing, and forever if the override fails to load.
   */
  fallback: ReactNode;
  /** Edge length in px. Defaults to `EngineTokens.iconSizeMd`. */
  size?: number;
  /**
   * CSS colour to tint with. Defaults to the loaded `text` token, then to
   * `EngineTokens.fallbackIconColor` — the same ladder as Dart's
   * `IconTheme.of(context).color ?? ThemeColor.token('text', …)`.
   */
  color?: string;
  className?: string;
  style?: CSSProperties;
}

export function ThemeIcon({
  slot,
  fallback,
  size = EngineTokens.iconSizeMd,
  color,
  className,
  style,
}: ThemeIconProps) {
  const url = useThemeIconUrl(slot);
  const defaultTint = useThemeToken('text', EngineTokens.fallbackIconColor);
  const [loadedUrl, setLoadedUrl] = useState<string | null>(null);

  useEffect(() => {
    if (url === null || typeof Image === 'undefined') return;
    let cancelled = false;
    const probe = new Image();
    probe.onload = () => {
      if (!cancelled) setLoadedUrl(url);
    };
    // No onerror handler on purpose: a failed probe simply never promotes the
    // URL, so the fallback stays. Retrying a 404 every render would be worse.
    probe.src = url;
    return () => {
      cancelled = true;
    };
  }, [url]);

  if (url === null || loadedUrl !== url) return <>{fallback}</>;

  const tint = color ?? toCss(defaultTint);
  const mask = `url("${url}")`;
  return (
    <span
      aria-hidden
      className={className}
      style={{
        display: 'inline-block',
        width: size,
        height: size,
        backgroundColor: tint,
        maskImage: mask,
        WebkitMaskImage: mask,
        maskSize: 'contain',
        WebkitMaskSize: 'contain',
        maskRepeat: 'no-repeat',
        WebkitMaskRepeat: 'no-repeat',
        maskPosition: 'center',
        WebkitMaskPosition: 'center',
        ...style,
      }}
    />
  );
}
