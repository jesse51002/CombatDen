// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// layouts/class_spec_brief.dart.
//
// `ClassFormat.specBrief` — THE FACTS FIRST, THE POSTER LAST. The specifics
// become a label/value table, instructor and location compress to strips, and
// the reserve action sits at the END of the content instead of pinned. For the
// member who has taken this class fifty times and wants the time and the mat.
//
// "NO BANNER" IS A TREATMENT CLAIM, NOT A CONTENT ONE — the single most
// misreadable line in the whole `ClassFormat` enum. The Dart's own class doc
// completes the sentence: "No banner: the photo becomes a thumb inline with the
// title", and `class_invariants_test.dart` asserts
// `expectExactlyOne(ClassImageBanner)` for all five values, commented "the
// photo is never dropped — `specBrief` shrinks it to a thumb, which is still
// one banner". So the photo is here, same URL, 96px square, passed into the
// meta's `leading` slot.
//
// That is what keeps the invariant intact without argument. Had the image
// really been dropped, the question would be whether it carried INFORMATION (a
// rearrangement may not lose any) or decoration. It never arises.

import { ClassScreenTopbar } from '../parts/ClassScreenTopbar';
import { SectionDivider } from '../parts/SectionDivider';
import { ClassDetailsSection } from '../sections/ClassDetailsSection';
import { ClassImageBanner } from '../sections/ClassImageBanner';
import { ClassInstructorSection } from '../sections/ClassInstructorSection';
import { ClassLocationSection } from '../sections/ClassLocationSection';
import { ClassMetaSection } from '../sections/ClassMetaSection';
import { ClassReserveFooter } from '../sections/ClassReserveFooter';

import type { ClassLayoutProps } from './layoutProps';
import styles from './layouts.module.css';

export function ClassSpecBrief({ detail, gymName, gymLogoSrc }: ClassLayoutProps) {
  const cls = detail.classData;
  return (
    <div className={styles.scrollBody}>
      <ClassScreenTopbar gymName={gymName} gymLogoSrc={gymLogoSrc} />
      <div className={styles.specBody}>
        <ClassMetaSection
          detail={detail}
          layout="specTable"
          leading={<ClassImageBanner imageUrl={cls.imageUrl} treatment="thumb" />}
        />
        <SectionDivider />
        {/* `Column(start, spacing: spacingLarge)` — the two compressed strips. */}
        <div className={styles.specStrips}>
          <ClassInstructorSection
            bio={cls.instructorBio}
            imageUrl={cls.instructorImageUrl}
            layout="row"
          />
          <ClassLocationSection address={detail.address} mapSrc={detail.mapSrc} layout="row" />
        </div>
        <SectionDivider />
        <ClassDetailsSection description={cls.description} />
        <ClassReserveFooter position="inline" />
      </div>
    </div>
  );
}
