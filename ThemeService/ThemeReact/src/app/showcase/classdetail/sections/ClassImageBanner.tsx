// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// widgets/class_image_banner.dart — the class photo, at whatever size the
// arrangement asks for.
//
// EVERY TREATMENT RENDERS THE SAME IMAGE FROM THE SAME URL. This is size and
// shape only. No `class_format` drops the photo: `specBrief`'s doc line reads
// "No banner", and that is a claim about the TREATMENT — the full-bleed strip
// is gone, the photo survives as a thumb inline with the title. The Dart enum's
// own comment says so ("the photo becomes a thumb inline with the title") and
// `class_invariants_test.dart` pins it with `expectExactlyOne(ClassImageBanner)`
// for all five values, commented "the photo is never dropped".
//
// That distinction is the whole reason the invariant survives here. Had
// `specBrief` really dropped the image, the question would be whether the photo
// carried INFORMATION or decoration — and a rearrangement may not lose
// information. It does not arise: the image is still on the screen, still the
// same URL, just 96px square.

import { cx } from '../../cx';
import { CLASS_PART, classPart } from '../classParts';

import styles from './ClassImageBanner.module.css';
import { DegradingImage } from './DegradingImage';

/** `ClassBannerTreatment` — how a layout sizes and places the photo. */
export type ClassBannerTreatment = 'banner' | 'compact' | 'hero' | 'backdrop' | 'thumb';

// `string | undefined` because a CSS-module key is typed that way under
// `noUncheckedIndexedAccess`; `cx` already drops an undefined class name.
const TREATMENT_CLASS: Readonly<Record<ClassBannerTreatment, string | undefined>> = {
  banner: styles.banner,
  compact: styles.compact,
  hero: styles.hero,
  backdrop: styles.backdrop,
  thumb: styles.thumb,
};

export interface ClassImageBannerProps {
  imageUrl: string;
  /** Defaults to `banner`, the treatment that ships. */
  treatment?: ClassBannerTreatment;
}

export function ClassImageBanner({ imageUrl, treatment = 'banner' }: ClassImageBannerProps) {
  return (
    <DegradingImage
      src={imageUrl}
      className={styles.img}
      frameClassName={cx(styles.frame, TREATMENT_CLASS[treatment])}
      frameProps={classPart(CLASS_PART.banner)}
    />
  );
}
