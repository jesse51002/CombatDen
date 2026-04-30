/// Hardcoded mock data for the MemberApp preview screen.
///
/// The screen lets a gym admin configure how their member-facing mobile
/// app looks and what rewards are available. Everything below mirrors the
/// shape of the real backend payload that will eventually replace it.
library;

/// The four supported gym types — admin picks one and the member app
/// reskins around it.
enum GymType { mma, judoBjj, boxingKickboxing, karateTaekwondo }

/// A configurable reward in the in-app rewards store.
class RewardItem {
  final String brand;
  final String name;
  final String discount;
  final int points;
  final String imageAsset;

  const RewardItem({
    required this.brand,
    required this.name,
    required this.discount,
    required this.points,
    required this.imageAsset,
  });
}

/// A reward template the admin can add to the store.
class RewardTemplate {
  final String brand;
  final String title;
  final String? subtitle;
  final String imageAsset;

  const RewardTemplate({
    required this.brand,
    required this.title,
    this.subtitle,
    required this.imageAsset,
  });
}

class MemberAppPreviewData {
  final String gymName;
  final String gymLogoAsset;
  final GymType selectedGymType;
  final List<RewardItem> rewards;
  final List<RewardTemplate> addableRewards;

  const MemberAppPreviewData({
    required this.gymName,
    required this.gymLogoAsset,
    required this.selectedGymType,
    required this.rewards,
    required this.addableRewards,
  });
}

const MemberAppPreviewData kMockMemberAppPreview = MemberAppPreviewData(
  gymName: 'Global MMA',
  gymLogoAsset: 'assets/images/gym_logo_global_mma.png',
  selectedGymType: GymType.mma,
  rewards: [
    RewardItem(
      brand: 'Venom',
      name: 'Hand wraps',
      discount: '30% off',
      points: 1500,
      imageAsset: 'assets/images/reward_hand_wraps.png',
    ),
    RewardItem(
      brand: 'Global MMA',
      name: 'Bring a friend to a class',
      discount: 'Free',
      points: 1500,
      imageAsset: 'assets/images/reward_bring_friend.png',
    ),
    RewardItem(
      brand: 'Global MMA',
      name: 'An extra class',
      discount: 'Free',
      points: 1500,
      imageAsset: 'assets/images/reward_extra_class.png',
    ),
    RewardItem(
      brand: 'Venom',
      name: 'Boxing Gloves',
      discount: '\$20 off',
      points: 3000,
      imageAsset: 'assets/images/reward_boxing_gloves.png',
    ),
    RewardItem(
      brand: 'Global MMA',
      name: 'Global MMA tshirt',
      discount: 'Free',
      points: 3000,
      imageAsset: 'assets/images/reward_gym_tshirt.png',
    ),
    RewardItem(
      brand: 'Global MMA',
      name: 'Private Training Session',
      discount: '50% off',
      points: 3000,
      imageAsset: 'assets/images/reward_private_training.png',
    ),
  ],
  addableRewards: [
    RewardTemplate(
      brand: 'Global MMA',
      title: 'Membership Discount',
      subtitle: '% off or \$ discount',
      imageAsset: 'assets/images/reward_membership_discount.png',
    ),
    RewardTemplate(
      brand: 'Global MMA',
      title: 'Gym branded gear',
      imageAsset: 'assets/images/reward_gym_tshirt.png',
    ),
    RewardTemplate(
      brand: 'Global MMA',
      title: 'Film and Review Session',
      imageAsset: 'assets/images/reward_film_review.png',
    ),
    RewardTemplate(
      brand: 'Global MMA',
      title: 'Custom',
      subtitle: 'Anything you want',
      imageAsset: 'assets/images/reward_custom.png',
    ),
  ],
);
