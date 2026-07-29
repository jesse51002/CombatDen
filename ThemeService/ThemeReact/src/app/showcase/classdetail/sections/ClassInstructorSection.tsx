// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// widgets/class_instructor_section.dart — "Instructor" over the bio, with a
// circular headshot.
//
// THE BIO AND THE HEADSHOT ARE IN EVERY VALUE. Only where the headshot sits and
// how big it is changes: trailing at 132 (ships), centred above the bio at 132
// (for a narrow pane), or leading at 56 (the compact strip).

import { CLASS_PART, classPart } from '../classParts';
import { SubtitleSection } from '../parts/SubtitleSection';

import { cx } from '../../cx';

import styles from './ClassInstructorSection.module.css';
import { DegradingImage } from './DegradingImage';

/** `ClassInstructorLayout`. */
export type ClassInstructorLayout = 'avatarTrailing' | 'avatarTop' | 'row';

// See ./ClassImageBanner.tsx on the `| undefined`.
const LAYOUT_CLASS: Readonly<Record<ClassInstructorLayout, string | undefined>> = {
  avatarTrailing: styles.avatarTrailing,
  avatarTop: styles.avatarTop,
  row: styles.row,
};

export interface ClassInstructorSectionProps {
  bio: string;
  imageUrl: string;
  /** Defaults to `avatarTrailing`, the arrangement that ships. */
  layout?: ClassInstructorLayout;
}

export function ClassInstructorSection({
  bio,
  imageUrl,
  layout = 'avatarTrailing',
}: ClassInstructorSectionProps) {
  const avatar = (
    <DegradingImage
      src={imageUrl}
      className={styles.avatarImg}
      // `_kAvatarSm` 56 on the compact strip, `_kAvatarLg` 132 elsewhere.
      frameClassName={cx(styles.avatar, layout === 'row' && styles.avatarSmall)}
    />
  );
  const text = <p className={styles.bio}>{bio}</p>;

  return (
    <SubtitleSection
      title="Instructor"
      spacing="medium"
      markerProps={classPart(CLASS_PART.instructor)}
    >
      <div className={cx(styles.content, LAYOUT_CLASS[layout])}>
        {/* `avatarTrailing` puts the bio first; the other two lead with the headshot. */}
        {layout === 'avatarTrailing' ? (
          <>
            {text}
            {avatar}
          </>
        ) : (
          <>
            {avatar}
            {text}
          </>
        )}
      </div>
    </SubtitleSection>
  );
}
