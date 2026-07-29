// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// class_item/class_item_rule.dart.
//
// The separating line beneath a class row. `hairline` is the lighter weight the
// `dense` treatment uses, where a 2px rule would out-shout the row it
// separates.

import { cx } from '../../cx';

import styles from './ClassItemRule.module.css';

export interface ClassItemRuleProps {
  hairline?: boolean;
}

export function ClassItemRule({ hairline = false }: ClassItemRuleProps) {
  return <div className={cx(styles.divider, hairline && styles.hairline)} />;
}
