// Ports ../../../../../CRM/lib/shared/widgets/section_card.dart.
//
// A panel with the standard card background and `radiusBig` corners. Used as
// the chrome around major regions. Kept minimal, exactly as the Dart widget is.

import type { CSSProperties, ReactNode } from 'react';

import styles from './SectionCard.module.css';

export interface SectionCardProps {
  children: ReactNode;
  /** Defaults to `paddingBig` (32), like the Dart widget. */
  padding?: string;
  /** Defaults to `radiusBig` (12). */
  borderRadius?: number;
  backgroundColor?: string;
}

export function SectionCard({
  children,
  padding,
  borderRadius,
  backgroundColor,
}: SectionCardProps) {
  const style: CSSProperties = {
    ...(padding === undefined ? {} : { padding }),
    ...(borderRadius === undefined ? {} : { borderRadius: `${borderRadius}px` }),
    ...(backgroundColor === undefined ? {} : { background: backgroundColor }),
  };
  return (
    <div className={styles.card} style={style}>
      {children}
    </div>
  );
}
