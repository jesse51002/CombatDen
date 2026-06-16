/// A card captured at checkout for the one-time charge only:
/// the Stripe payment-method id (`pm_…`) the wire request
/// carries, plus the brand/last-four for the chip the
/// payment step shows, and whether to promote it to the
/// payer's saved default after a successful charge.
///
/// This card is never stored on its own — it pays today's
/// one-time invoice and, unless [setAsDefault], is dropped.
class CustomCardCapture {
  final String pmId;
  final String brand;
  final String lastFour;
  final bool setAsDefault;

  const CustomCardCapture({
    required this.pmId,
    required this.brand,
    required this.lastFour,
    required this.setAsDefault,
  });

  /// `Visa ···· 4242` — the chip label.
  String get display => '$brand ···· $lastFour';

  CustomCardCapture copyWith({bool? setAsDefault}) =>
      CustomCardCapture(
        pmId: pmId,
        brand: brand,
        lastFour: lastFour,
        setAsDefault: setAsDefault ?? this.setAsDefault,
      );
}
