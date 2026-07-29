// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// layouts/parts/class_hero_scrim.dart — a fade from the page background DOWN
// over the top of the class photo, so the topbar stays legible on the two
// arrangements that lay it over the image.
//
// Keyed to `background` rather than to a literal black: a light preset fades to
// its own canvas, and the text tokens keep the contrast they were picked for.

import styles from './ClassHeroScrim.module.css';

export function ClassHeroScrim() {
  return <div className={styles.scrim} />;
}
