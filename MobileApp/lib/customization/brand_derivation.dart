/// The six derivation keys the CustomizationService ships per
/// colour slot (`primary.second`, `primary.third`, `primary.card`,
/// `primary.popup`, `primary.dark`, `primary.light`, and the same
/// six for every other slot).
///
/// The values are plain `String`s — they are what the wire and the
/// `CustomizationColor.derivations` map are keyed by — so this
/// class is a typed accessor, not an enum. Passing
/// `BrandDerivation.card` into `BrandColor.color(...)` is the same
/// as passing the literal `'card'`, but a typo in the literal
/// won't surface until runtime.
class BrandDerivation {
  // Private constructor to prevent instantiation
  BrandDerivation._();

  static const String second = 'second';
  static const String third = 'third';
  static const String card = 'card';
  static const String popup = 'popup';
  static const String dark = 'dark';
  static const String light = 'light';
}
