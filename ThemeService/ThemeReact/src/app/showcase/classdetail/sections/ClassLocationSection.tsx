// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// widgets/class_location_section.dart — "Location" over a static map preview
// and the street address.
//
// THE MAP PREVIEW AND THE ADDRESS ARE IN BOTH VALUES. Only the map's size and
// the direction they stack change: full-width above the address (ships), or a
// 116px-wide strip leading it.
//
// THE MAP IS A BUNDLED PNG, not a tile request, and that is the Dart's own
// choice rather than a showcase shortcut: `ApiImage.classAsset` resolves
// `assets/classes/class_location_map.png` from the member app's own bundle. So
// the honest port is the same still image, copied from `MobileApp/assets/
// classes/` — exactly how ../../assets/'s two profile belt PNGs arrived. A live
// tile provider would put a keyed network round trip on a screen whose whole
// point is to render with the backend unreachable, and it would show a real
// place the demo address does not describe.

import { CLASS_PART, classPart } from '../classParts';
import { SubtitleSection } from '../parts/SubtitleSection';

import { cx } from '../../cx';

import styles from './ClassLocationSection.module.css';
import { DegradingImage } from './DegradingImage';

/** `ClassLocationLayout`. */
export type ClassLocationLayout = 'stacked' | 'row';

export interface ClassLocationSectionProps {
  address: string;
  mapSrc: string;
  /** Defaults to `stacked`, the arrangement that ships. */
  layout?: ClassLocationLayout;
}

export function ClassLocationSection({
  address,
  mapSrc,
  layout = 'stacked',
}: ClassLocationSectionProps) {
  return (
    <SubtitleSection
      title="Location"
      spacing="medium"
      markerProps={classPart(CLASS_PART.location)}
    >
      <div className={cx(styles.content, layout === 'row' && styles.row)}>
        <DegradingImage
          src={mapSrc}
          className={styles.mapImg}
          frameClassName={cx(styles.map, layout === 'row' && styles.mapSmall)}
        />
        <p className={styles.address}>{address}</p>
      </div>
    </SubtitleSection>
  );
}
