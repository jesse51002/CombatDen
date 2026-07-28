// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// layouts/class_banner_stack.dart.
//
// `ClassFormat.bannerStack` — THE ARRANGEMENT THAT SHIPS TODAY. Photo, meta,
// then three divided sections down one scroll, with the reserve action pinned
// beneath it. The Dart reproduces the previous `ClassScreen` body widget for
// widget so a tenant with no layout slot sees no change; this is the same
// baseline on the web, and .../__tests__/classFormats.test.tsx pins its
// element set as the one every other value is measured against.

import { ClassScreenTopbar } from '../parts/ClassScreenTopbar';
import { ClassSectionStack } from '../parts/ClassSectionStack';
import { ClassDetailsSection } from '../sections/ClassDetailsSection';
import { ClassImageBanner } from '../sections/ClassImageBanner';
import { ClassInstructorSection } from '../sections/ClassInstructorSection';
import { ClassLocationSection } from '../sections/ClassLocationSection';
import { ClassMetaSection } from '../sections/ClassMetaSection';
import { ClassReserveFooter } from '../sections/ClassReserveFooter';

import styles from './layouts.module.css';
import type { ClassLayoutProps } from './layoutProps';

export function ClassBannerStack({ detail, gymName, gymLogoSrc }: ClassLayoutProps) {
  const cls = detail.classData;
  return (
    <div className={styles.column}>
      <div className={styles.scrollBody}>
        <ClassScreenTopbar gymName={gymName} gymLogoSrc={gymLogoSrc} />
        <ClassImageBanner imageUrl={cls.imageUrl} treatment="banner" />
        <ClassSectionStack
          sections={[
            <ClassMetaSection key="meta" detail={detail} />,
            <ClassDetailsSection key="details" description={cls.description} />,
            <ClassInstructorSection
              key="instructor"
              bio={cls.instructorBio}
              imageUrl={cls.instructorImageUrl}
            />,
            <ClassLocationSection key="location" address={detail.address} mapSrc={detail.mapSrc} />,
          ]}
        />
      </div>
      <ClassReserveFooter />
    </div>
  );
}
