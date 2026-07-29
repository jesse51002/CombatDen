// Ports ../../../../../CRM/lib/shared/widgets/filter_pills.dart.
//
// A wrapping row of compact, single-select filter pills — sized for many
// options, like a feed's category filters.
//
// DEVIATION: Dart wraps them in `IntrinsicWrap` rather than `Wrap`, because
// pills there sit inside `IntrinsicHeight`-driven layouts that need a run-aware
// height. CSS flex-wrap reports its wrapped height natively, so the distinction
// has no counterpart here — `flex-wrap: wrap` IS `IntrinsicWrap`.

import styles from './FilterPills.module.css';
import { cx } from './cx';

export interface FilterPillsProps {
  labels: readonly string[];
  selectedIndex: number;
  onSelected: (index: number) => void;
}

export function FilterPills({ labels, selectedIndex, onSelected }: FilterPillsProps) {
  return (
    <div className={styles.pills}>
      {labels.map((label, i) => (
        <button
          key={label}
          type="button"
          className={cx(styles.pill, i === selectedIndex && styles.selected)}
          aria-pressed={i === selectedIndex}
          onClick={() => onSelected(i)}
        >
          {label}
        </button>
      ))}
    </div>
  );
}
