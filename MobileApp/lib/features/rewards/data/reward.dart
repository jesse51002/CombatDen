/// One points-store reward as served by the VideoService
/// (`GET /gyms/{gymId}` → `GymDetail.rewards`). Field names mirror the API so
/// the JSON parse stays mechanical. See `../VideoService/schema/gym.py`
/// (`RewardCard`).
class Reward {
  const Reward({
    required this.title,
    required this.imageUrl,
    required this.priceLabel,
    required this.pointsCost,
  });

  final String title;

  /// Network image url (the gym serves URLs, not bundled assets).
  final String imageUrl;

  /// What the member pays on top of points: "Free", "30% off".
  final String priceLabel;
  final int pointsCost;

  factory Reward.fromJson(Map<String, dynamic> json) => Reward(
    title: (json['title'] as String?) ?? '',
    imageUrl: (json['image_url'] as String?) ?? '',
    priceLabel: (json['price_label'] as String?) ?? '',
    pointsCost: (json['points_cost'] as int?) ?? 0,
  );
}
