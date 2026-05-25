/// The seven derivation keys the CustomizationService ships per
/// colour slot (`primary.second`, `primary.third`, `primary.card`,
/// `primary.popup`, `primary.dark`, `primary.light`,
/// `primary.regular_text`, and the same seven for every other slot).
///
/// `regular_text` is the readable colour for text/labels painted ON
/// that slot's colour (e.g. a label on a primary-filled button): the
/// body text colour when it clears WCAG AA on the fill, otherwise
/// whichever of text/background contrasts better.
///
/// The values are plain `String`s — they are what the wire and the
/// `CustomizationColor.derivations` map are keyed by — so this
/// class is a typed accessor, not an enum. Passing
/// `ThemeDerivation.card` into `ThemeColor.color(...)` is the same
/// as passing the literal `'card'`, but a typo in the literal
/// won't surface until runtime.
class ThemeDerivation {
  // Private constructor to prevent instantiation
  ThemeDerivation._();

  static const String second = 'second';
  static const String third = 'third';
  static const String card = 'card';
  static const String popup = 'popup';
  static const String dark = 'dark';
  static const String light = 'light';
  static const String regularText = 'regular_text';
}
