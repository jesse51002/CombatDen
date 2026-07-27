// Ports ../../../../../../CRM/lib/showcase/home/date_tab.dart — a clone of
// MobileApp's `DateTab`: one date pill in the home date row, bottom-bordered
// when selected. Tappable; a preview no-op.

import { cx } from '../cx';

import styles from './DateTab.module.css';

export interface DateTabProps {
  label: string;
  isSelected: boolean;
  onTap?: (() => void) | undefined;
}

export function DateTab({ label, isSelected, onTap }: DateTabProps) {
  return (
    <button
      type="button"
      className={cx(styles.tab, isSelected && styles.selected)}
      aria-pressed={isSelected}
      onClick={onTap}
    >
      {label}
    </button>
  );
}
