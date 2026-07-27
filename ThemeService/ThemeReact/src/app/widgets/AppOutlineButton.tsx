// Ports ../../../../../CRM/lib/shared/widgets/app_outline_button.dart.
//
// Outlined button: `buttonBorder` (2) stroke in the ink colour, `radiusBig`
// corners, an h3 label, and the standard paddingSmall/spacingMedium padding.
// `fullWidth` stretches it — which is how the phone-mode side pane's
// "← Back to library" renders.
//
// DEVIATION: the Dart widget exposes eight overrides (border colour/width, text
// colour/style, padding, radius, icon). Only the ones this app actually uses
// are carried over — `fullWidth`, `onPressed`, and an optional leading icon —
// because an unused override is a value with no call site to keep it honest.
// Everything else reads the tokens through the CSS Module.

import type { ReactNode } from 'react';

import styles from './AppOutlineButton.module.css';
import { cx } from './cx';

export interface AppOutlineButtonProps {
  text: string;
  onPressed?: (() => void) | undefined;
  fullWidth?: boolean;
  icon?: ReactNode;
}

export function AppOutlineButton({ text, onPressed, fullWidth = false, icon }: AppOutlineButtonProps) {
  return (
    <button
      type="button"
      className={cx(styles.button, fullWidth && styles.fullWidth)}
      onClick={onPressed}
      disabled={onPressed === undefined}
    >
      {icon}
      <span>{text}</span>
    </button>
  );
}
