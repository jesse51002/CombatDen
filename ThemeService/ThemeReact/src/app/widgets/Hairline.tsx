// Ports ../../../../../CRM/lib/shared/widgets/hairline.dart.
//
// A 1px rule in the divider color used to separate de-carded sections.
// Horizontal by default; set `vertical` to separate side-by-side columns.

import styles from './Hairline.module.css';

export interface HairlineProps {
  vertical?: boolean;
}

export function Hairline({ vertical = false }: HairlineProps) {
  return <div className={vertical ? styles.vertical : styles.horizontal} />;
}
