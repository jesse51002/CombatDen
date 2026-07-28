// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// layouts/parts/class_tab_bar.dart — the `sectionTabs` selector: one tab per
// section sharing the pane below it.
//
// PRESENTATION ONLY. It selects which of the screen's EXISTING sections is on
// top and adds no content of its own — which is what keeps `sectionTabs` an
// arrangement rather than a new screen.

import { cx } from '../../cx';

import styles from './ClassTabBar.module.css';

export interface ClassTabBarProps {
  labels: readonly string[];
  index: number;
  onSelect: (index: number) => void;
}

export function ClassTabBar({ labels, index, onSelect }: ClassTabBarProps) {
  return (
    <div className={styles.bar} role="tablist">
      {labels.map((label, i) => (
        <button
          key={label}
          type="button"
          role="tab"
          aria-selected={i === index}
          className={cx(styles.tab, i === index && styles.active)}
          onClick={() => {
            onSelect(i);
          }}
        >
          {label}
        </button>
      ))}
    </div>
  );
}
