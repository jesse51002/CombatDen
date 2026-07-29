// Ports ../../../../../CRM/lib/shared/widgets/app_primary_button.dart.
//
// The landing page's signature gradient CTA — a sapphire→accent-dark gradient
// with the layered blue shadow, a white label, and an optional leading icon.
// The Dart widget's own docstring points at `GWButton` primary in
// LandingPage/hifi/chrome.jsx; ../chrome/GWButton.tsx is that button ported
// directly, and this is the CRM's token-driven version of the same look. Both
// exist here for the same reason both exist in the CRM: the chrome belongs to
// the marketing site's design system, everything under the nav to the CRM's.
//
// DEVIATION: the Dart widget's `backgroundColor` (solid-fill) override and its
// `onFill` auto-contrast are not carried over — this app has no destructive or
// status-coloured primary action, so there is no call site to keep them honest.
// `isLoading` and `fullWidth` are.

import type { ReactNode } from 'react';

import styles from './AppPrimaryButton.module.css';
import { AppSpinner } from './AppSpinner';
import { cx } from './cx';

export interface AppPrimaryButtonProps {
  text: string;
  onPressed?: (() => void) | undefined;
  isLoading?: boolean;
  fullWidth?: boolean;
  icon?: ReactNode;
}

export function AppPrimaryButton({
  text,
  onPressed,
  isLoading = false,
  fullWidth = false,
  icon,
}: AppPrimaryButtonProps) {
  const enabled = onPressed !== undefined && !isLoading;
  return (
    <button
      type="button"
      className={cx(styles.button, fullWidth && styles.fullWidth)}
      onClick={onPressed}
      disabled={!enabled}
    >
      {isLoading ? (
        <AppSpinner size={20} onAccent />
      ) : (
        <>
          {icon}
          <span>{text}</span>
        </>
      )}
    </button>
  );
}
