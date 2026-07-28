// Ports ../../../../../../CRM/lib/showcase/home/date_tab.dart — a clone of
// MobileApp's `DateTab`: one date pill in the home date row — and, for the
// second selected-state, MobileApp's own `.../class_schedule/date_tab.dart`
// (`DateTabStyle`).
//
// PRESENTATION ONLY. The tab count, the labels and the tap contract are the
// same either way; `style` changes nothing but how the selected day marks
// itself.

import { cx } from '../cx';

import styles from './DateTab.module.css';

/** `DateTabStyle`. */
export type DateTabStyle =
  /** Shipped today: bare label with a rule under the selected day. */
  | 'underline'
  /**
   * A filled chip per day, for formats that want the date rail to read as a
   * control rather than as a rail.
   */
  | 'segmented';

export interface DateTabProps {
  label: string;
  isSelected: boolean;
  style?: DateTabStyle;
  onTap?: (() => void) | undefined;
}

export function DateTab({ label, isSelected, style = 'underline', onTap }: DateTabProps) {
  return (
    <button
      type="button"
      className={cx(
        styles.tab,
        style === 'segmented' && styles.segmented,
        isSelected && styles.selected,
      )}
      aria-pressed={isSelected}
      onClick={onTap}
    >
      {label}
    </button>
  );
}
