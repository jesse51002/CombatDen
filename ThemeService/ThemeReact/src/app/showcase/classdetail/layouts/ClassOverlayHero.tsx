// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// layouts/class_overlay_hero.dart.
//
// `ClassFormat.overlayHero` — THE META RIDES THE PHOTO. A taller 4:5 hero
// carries the topbar at its top and the meta block at its bottom, both behind a
// fade to the page background.
//
// THE INSTRUCTOR IS PROMOTED above the description, and that reordering is the
// arrangement's whole argument: at a combat gym the coach is the reason to
// book. Same four sections as `bannerStack`, three of them in the stack because
// the meta has moved onto the image.

import { ClassHeroScrim } from '../parts/ClassHeroScrim';
import { ClassScreenTopbar } from '../parts/ClassScreenTopbar';
import { ClassSectionStack } from '../parts/ClassSectionStack';
import { ClassDetailsSection } from '../sections/ClassDetailsSection';
import { ClassImageBanner } from '../sections/ClassImageBanner';
import { ClassInstructorSection } from '../sections/ClassInstructorSection';
import { ClassLocationSection } from '../sections/ClassLocationSection';
import { ClassMetaSection } from '../sections/ClassMetaSection';
import { ClassReserveFooter } from '../sections/ClassReserveFooter';

import type { ClassLayoutProps } from './layoutProps';
import styles from './layouts.module.css';

export function ClassOverlayHero({ detail, gymName, gymLogoSrc }: ClassLayoutProps) {
  const cls = detail.classData;
  return (
    <div className={styles.column}>
      <div className={styles.scrollBody}>
        {/* `_Hero` — `Stack(banner, scrim, topbar, meta)`. */}
        <div className={styles.hero}>
          <ClassImageBanner imageUrl={cls.imageUrl} treatment="hero" />
          <ClassHeroScrim />
          <div className={styles.heroTop}>
            <ClassScreenTopbar gymName={gymName} gymLogoSrc={gymLogoSrc} />
          </div>
          <div className={styles.heroBottom}>
            <ClassMetaSection detail={detail} layout="overlay" />
          </div>
        </div>
        <ClassSectionStack
          sections={[
            <ClassInstructorSection
              key="instructor"
              bio={cls.instructorBio}
              imageUrl={cls.instructorImageUrl}
            />,
            <ClassDetailsSection key="details" description={cls.description} />,
            <ClassLocationSection key="location" address={detail.address} mapSrc={detail.mapSrc} />,
          ]}
        />
      </div>
      <ClassReserveFooter />
    </div>
  );
}
