/// Dummy data for the showcase Points Store — clone of MobileApp's
/// `mock_points_store.dart`, brand name generalized.
library;

class ShowcasePointsStoreItem {
  const ShowcasePointsStoreItem({
    required this.title,
    required this.priceLabel,
    required this.pointsCost,
    required this.imageAsset,
  });

  final String title;
  final String priceLabel;
  final int pointsCost;
  final String imageAsset;
}

class ShowcasePointsStoreData {
  const ShowcasePointsStoreData({
    required this.gymName,
    required this.gymLogoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    required this.totalPoints,
    required this.items,
  });

  final String gymName;
  final String gymLogoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;
  final int totalPoints;
  final List<ShowcasePointsStoreItem> items;
}

const showcasePointsStoreData = ShowcasePointsStoreData(
  gymName: 'Your Gym',
  gymLogoAsset: 'gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
  totalPoints: 3400,
  items: [
    ShowcasePointsStoreItem(
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 800,
      imageAsset: 'reward_bring_friend.png',
    ),
    ShowcasePointsStoreItem(
      title: 'Hand wraps',
      priceLabel: '30% off',
      pointsCost: 1500,
      imageAsset: 'reward_hand_wraps.png',
    ),
    ShowcasePointsStoreItem(
      title: 'Private Training\n(15 min)',
      priceLabel: 'Free',
      pointsCost: 1800,
      imageAsset: 'reward_private_training_short.png',
    ),
    ShowcasePointsStoreItem(
      title: 'Gym t-shirt',
      priceLabel: 'Free',
      pointsCost: 2200,
      imageAsset: 'reward_mma_tshirt.png',
    ),
    ShowcasePointsStoreItem(
      title: 'Boxing gloves',
      priceLabel: '10% off',
      pointsCost: 2500,
      imageAsset: 'reward_gloves.png',
    ),
    ShowcasePointsStoreItem(
      title: 'Private Training',
      priceLabel: '50% off',
      pointsCost: 3500,
      imageAsset: 'reward_private_training.png',
    ),
  ],
);
