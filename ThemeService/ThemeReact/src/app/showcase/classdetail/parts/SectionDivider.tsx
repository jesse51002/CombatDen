// Ports ../../../../../../../MobileApp/lib/shared/widgets/dividers/
// section_divider.dart — the full-bleed hairline between major page sections.
//
// `Container(height: dividerThickness, color: text3rd)`. Note the colour: it is
// `text3rd`, NOT the `divider` token, which is what ../../support/
// ShowcaseTopbar.module.css's own bottom rule already uses. Reaching for
// `--sc-divider` here would be a quiet restyle rather than a port.

import styles from './SectionDivider.module.css';

export function SectionDivider() {
  return <div className={styles.divider} />;
}
