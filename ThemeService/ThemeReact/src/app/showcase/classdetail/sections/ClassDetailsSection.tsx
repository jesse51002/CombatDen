// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// widgets/class_details_section.dart — "Details" over the long-form
// description. `SubtitleSection(spacing: spacingMedium)` with a `pBig` /
// `text2nd` body.

import { CLASS_PART, classPart } from '../classParts';
import { SubtitleSection } from '../parts/SubtitleSection';

import styles from './ClassDetailsSection.module.css';

export interface ClassDetailsSectionProps {
  description: string;
}

export function ClassDetailsSection({ description }: ClassDetailsSectionProps) {
  return (
    <SubtitleSection
      title="Details"
      spacing="medium"
      markerProps={classPart(CLASS_PART.details)}
    >
      <p className={styles.body}>{description}</p>
    </SubtitleSection>
  );
}
