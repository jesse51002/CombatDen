/// Gym content injected into the showcase preview by the host app
/// (AppManagement), so the phone shows the *selected gym's* real rewards and
/// classes instead of the bundled samples.
///
/// These are deliberately minimal — exactly the fields the gym file carries
/// (`VideoService`'s reward / class cards). The showcase maps them onto its own
/// store-item / schedule-item models; class time slots are synthesised (the gym
/// file has no schedule). When the host passes nothing, the showcase falls back
/// to its bundled sample data, so it still renders offline.
library;

/// One points-store reward to preview (maps to a store-grid card).
class ShowcaseReward {
  const ShowcaseReward({
    required this.title,
    required this.imageUrl,
    required this.priceLabel,
    required this.pointsCost,
  });

  final String title;
  final String imageUrl; // network image (the gym serves URLs)
  final String priceLabel; // paid on top of points: "Free", "30% off"
  final int pointsCost;
}

/// One class card to preview (maps to a schedule row; its time slot is
/// synthesised by the schedule generator).
class ShowcaseClassInfo {
  const ShowcaseClassInfo({
    required this.name,
    required this.imageUrl,
    required this.instructorName,
  });

  final String name;
  final String imageUrl; // network image (the gym serves URLs)
  final String instructorName; // shown as the class mentor
}
