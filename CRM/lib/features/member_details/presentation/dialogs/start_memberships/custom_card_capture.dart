/// A one-off card captured at checkout for the one-time
/// charge only: the Stripe payment-method id (`pm_…`) the wire
/// request carries, plus the brand/last-four for the chip the
/// payment step shows.
///
/// This card is never saved and never becomes the default — it
/// pays today's one-time invoice once (attach → pay → detach)
/// and is then dropped. Changing the saved/default card is the
/// separate "Edit card on file" flow.
class CustomCardCapture {
  final String pmId;
  final String brand;
  final String lastFour;

  const CustomCardCapture({
    required this.pmId,
    required this.brand,
    required this.lastFour,
  });

  /// `Visa ···· 4242` — the chip label.
  String get display => '$brand ···· $lastFour';
}
