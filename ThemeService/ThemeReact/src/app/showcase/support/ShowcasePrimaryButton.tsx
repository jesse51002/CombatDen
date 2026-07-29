// Ports ../../../../../../CRM/lib/showcase/support/showcase_primary_button.dart
// — a clone of MobileApp's `AppPrimaryButton`: the primary action on the brand
// fill. Preview-only; `onPressed` defaults to a no-op.
//
// The Dart widget takes `Color` / `TextStyle` / `EdgeInsets` overrides. Here
// every override is a CSS STRING, because the value it overrides is a `--sc-*`
// variable rather than a resolved object — a caller writes
// `borderRadius: 'var(--sc-radius-big)'` and the button stays inside the token
// system instead of reintroducing literals at the call site.
//
// `primaryButtonText` (the label colour) is the theme's `regular_text`
// derivation of `primary` — the service's own AA-checked answer to "what reads
// on this fill", not a guess made here.

import type { ReactNode } from 'react';

import styles from './ShowcasePrimaryButton.module.css';

export interface ShowcasePrimaryButtonProps {
  text: string;
  onPressed?: (() => void) | undefined;
  fullWidth?: boolean | undefined;
  /** CSS colour. Defaults to `var(--sc-primary)`. */
  backgroundColor?: string | undefined;
  /** CSS colour. Defaults to `var(--sc-primary-button-text)`. */
  textColor?: string | undefined;
  /** CSS `font` shorthand. Defaults to `var(--sc-type-h3)`. */
  font?: string | undefined;
  /** CSS letter-spacing to pair with `font`. Defaults to `var(--sc-type-h3-ls)`. */
  letterSpacing?: string | undefined;
  /** CSS padding. Defaults to `var(--sc-spacing-medium) var(--sc-padding-small)`. */
  padding?: string | undefined;
  /** CSS length. Defaults to `var(--sc-radius-small)`. */
  borderRadius?: string | undefined;
  icon?: ReactNode;
}

export function ShowcasePrimaryButton({
  text,
  onPressed,
  fullWidth = false,
  backgroundColor,
  textColor,
  font,
  letterSpacing,
  padding,
  borderRadius,
  icon,
}: ShowcasePrimaryButtonProps) {
  return (
    <button
      type="button"
      className={styles.button}
      style={{
        ...(backgroundColor === undefined ? {} : { background: backgroundColor }),
        ...(textColor === undefined ? {} : { color: textColor }),
        ...(font === undefined ? {} : { font }),
        ...(letterSpacing === undefined ? {} : { letterSpacing }),
        ...(padding === undefined ? {} : { padding }),
        ...(borderRadius === undefined ? {} : { borderRadius }),
        ...(fullWidth ? { width: '100%' } : {}),
      }}
      onClick={onPressed}
    >
      {icon}
      <span>{text}</span>
    </button>
  );
}
