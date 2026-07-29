// The generated raster and vector assets, each on a plate.
//
// THE PLATE IS PAINTED IN THE THEME'S OWN BACKGROUND, and that is a
// correctness decision rather than a styling one. Every one of these assets is
// a transparent PNG or a mask-tinted SVG authored for the theme's ground: a
// white belt or a pale logo on this page's near-white chrome is invisible, and
// a dark one on it is a lie about what the member sees. The plate reproduces
// the surface the asset was made for, so what renders here is what renders in
// the app.
//
// Consequently a plate is NOT one of the CRM's white object cards (see
// ../../../../CRM/DESIGN.md §5) — it carries no white fill and no shadow, only
// the hairline that keeps a pale theme's plate from dissolving into the page.

import type { ReactNode } from 'react';
import { useState } from 'react';
import type { Rgba } from 'theme-react';
import { ThemeIcon, toCss } from 'theme-react';

import { cx } from '../widgets/cx';

import { readableInk } from './artifactModel';
import styles from './AssetPlates.module.css';

export interface PlateProps {
  slot: string;
  /** The theme's ground — the surface this asset was authored against. */
  background: Rgba;
  /** Wide plates for the two full-scale artworks, square for the glyph set. */
  wide?: boolean;
}

export interface ImagePlateProps extends PlateProps {
  /** `null` when the pipeline produced no image for this slot. */
  url: string | null;
  /**
   * The visual-complexity tier the run assigned this image's prompt, which is
   * what picked the generator's quality. `''` when the run stamped none.
   */
  complexity?: string;
}

export function ImagePlate({
  slot,
  url,
  background,
  complexity = '',
  wide = false,
}: ImagePlateProps) {
  const ink = toCss(readableInk(background));
  return (
    <figure className={styles.plate}>
      <Surface background={background} wide={wide}>
        {url === null ? <Missing ink={ink} /> : <PlateImage url={url} slot={slot} ink={ink} />}
      </Surface>
      {/* The tier rides the existing kind slot rather than earning a mark of
          its own: both are one-word facts about the file, the section head
          says what a tier is, and a badge here would be the first boxed
          object on a sheet that has none. */}
      <Caption slot={slot} kind={complexity === '' ? 'png' : `${complexity} · png`} />
    </figure>
  );
}

export interface IconPlateProps extends PlateProps {
  /** Whether the slot exists on the wire at all. */
  present: boolean;
}

export function IconPlate({ slot, present, background, wide = false }: IconPlateProps) {
  const ink = toCss(readableInk(background));
  return (
    <figure className={styles.plate}>
      <Surface background={background} wide={wide}>
        {present ? (
          // Rendered through the runtime's own component, not an <img>: these
          // ship as monochrome SVGs that the app recolours with a CSS mask, so
          // drawing them any other way would show a shape the product never
          // paints. The tint defaults to the theme's `text` token — which is
          // the right ink for this plate, because the plate is its background.
          <ThemeIcon slot={slot} size={44} fallback={<Probing ink={ink} />} />
        ) : (
          <Missing ink={ink} />
        )}
      </Surface>
      <Caption slot={slot} kind="svg" />
    </figure>
  );
}

function Surface({
  background,
  wide,
  children,
}: {
  background: Rgba;
  wide: boolean;
  children: ReactNode;
}) {
  return (
    <div
      className={cx(styles.surface, wide && styles.wide)}
      style={{ background: toCss(background) }}
    >
      {children}
    </div>
  );
}

function PlateImage({ url, slot, ink }: { url: string; slot: string; ink: string }) {
  const [failed, setFailed] = useState(false);
  if (failed) return <Missing ink={ink} label="failed to load" />;
  return (
    <img
      className={styles.art}
      src={url}
      // The slot id is the only honest description available: the pipeline
      // ships no alt text, and inventing one would describe art nobody read.
      alt={slot}
      // NOT lazy, deliberately. There are ten of them, the runtime's asset
      // warmer has already pulled the set, and this page is scrolled fast in
      // front of a buyer — pop-in as the deck moves is worse than the ~1s of
      // extra fetch it saves.
      decoding="async"
      onError={() => setFailed(true)}
    />
  );
}

/**
 * A plate's own status line. The ink is derived from the THEME's background,
 * never a chrome token: this text sits on a generated colour, and a fixed grey
 * that reads on a near-black ground disappears entirely on a mid-grey one.
 */
function Missing({ ink, label = 'not produced' }: { ink: string; label?: string }) {
  return (
    <span className={styles.missing} style={{ color: ink }}>
      {label}
    </span>
  );
}

/** Held while `ThemeIcon` probes the URL; it never asserts an outcome. */
function Probing({ ink }: { ink: string }) {
  return <span className={styles.probing} style={{ borderColor: ink }} />;
}

function Caption({ slot, kind }: { slot: string; kind: string }) {
  return (
    <figcaption className={styles.caption}>
      <span className={styles.slot}>{slot}</span>
      <span className={styles.kind}>{kind}</span>
    </figcaption>
  );
}
