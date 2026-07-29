// Ports ../../ThemeFlutter/lib/theme/theme_derivation.dart.

/**
 * The seven derivation keys ThemeService ships per colour slot
 * (`primary.second`, `primary.third`, `primary.card`, `primary.popup`,
 * `primary.dark`, `primary.light`, `primary.regular_text`, and the same seven
 * for every other slot).
 *
 * `regular_text` is the readable colour for text/labels painted ON that slot's
 * colour (e.g. a label on a primary-filled button): the body text colour when
 * it clears WCAG AA on the fill, otherwise whichever of text/background
 * contrasts better.
 *
 * The values are plain strings — they are what the wire and the
 * `ThemeColorValue.derivations` map are keyed by — so this is a typed accessor,
 * not an enum. `ThemeDerivation.card` is the same as the literal `'card'`, but
 * a typo in the literal would not surface until runtime.
 */
export const ThemeDerivation = Object.freeze({
  second: 'second',
  third: 'third',
  card: 'card',
  popup: 'popup',
  dark: 'dark',
  light: 'light',
  regularText: 'regular_text',
} as const);

export type ThemeDerivationKey = (typeof ThemeDerivation)[keyof typeof ThemeDerivation];
