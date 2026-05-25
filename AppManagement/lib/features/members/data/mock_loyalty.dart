/// Hardcoded data for the Member App "Loyalty Program" tab.
///
/// The loyalty program is points-based: members earn a single point
/// balance and spend it on rewards. Reward names mirror the member
/// app's points store (`MobileApp/.../mock_points_store.dart`) so the
/// admin store and the member store stay in sync. Field names match the
/// shape the real API will eventually return.
library;

/// A reward the gym offers in its points store.
class LoyaltyReward {
  final String title;

  /// What the member pays on top of points, e.g. "Free", "30% off".
  /// Stored the way the API hands it over; capitalized at display time.
  final String priceLabel;

  final int pointsCost;
  final String imageAsset;

  const LoyaltyReward({
    required this.title,
    required this.priceLabel,
    required this.pointsCost,
    required this.imageAsset,
  });
}

/// A starter the admin can add to their store from the "Add your own"
/// grid. The subtitle hints at what the admin will configure.
class RewardTemplate {
  final String title;
  final String? subtitle;
  final String imageAsset;

  const RewardTemplate({
    required this.title,
    this.subtitle,
    required this.imageAsset,
  });
}

/// A member redemption awaiting the admin's confirmation at the desk.
class PendingRedemption {
  final String memberName;
  final String rewardTitle;
  final String priceLabel;
  final int pointsCost;
  final String imageAsset;

  /// The code the member reads off their phone; the admin matches it.
  final String code;

  /// When the member requested it. Pre-formatted for the prototype.
  final String requestedAt;

  /// True once the admin has confirmed this redemption — the card then shows
  /// an "Approved" marker instead of the Review & confirm action.
  final bool approved;

  const PendingRedemption({
    required this.memberName,
    required this.rewardTitle,
    required this.priceLabel,
    required this.pointsCost,
    required this.imageAsset,
    required this.code,
    required this.requestedAt,
    this.approved = false,
  });
}

const List<LoyaltyReward> kMockLoyaltyRewards = [
  LoyaltyReward(
    title: 'Bring a friend',
    priceLabel: 'Free',
    pointsCost: 800,
    imageAsset: 'assets/images/reward_bring_friend.png',
  ),
  LoyaltyReward(
    title: 'Hand wraps',
    priceLabel: '30% off',
    pointsCost: 1500,
    imageAsset: 'assets/images/reward_hand_wraps.png',
  ),
  LoyaltyReward(
    title: 'Private Training (15 min)',
    priceLabel: 'Free',
    pointsCost: 1800,
    imageAsset: 'assets/images/reward_private_training.png',
  ),
  LoyaltyReward(
    title: 'Gym t-shirt',
    priceLabel: 'Free',
    pointsCost: 2200,
    imageAsset: 'assets/images/reward_gym_tshirt.png',
  ),
  LoyaltyReward(
    title: 'Boxing gloves',
    priceLabel: '10% off',
    pointsCost: 2500,
    imageAsset: 'assets/images/reward_boxing_gloves.png',
  ),
  LoyaltyReward(
    title: 'Private Training',
    priceLabel: '50% off',
    pointsCost: 3500,
    imageAsset: 'assets/images/reward_private_training.png',
  ),
];

const List<RewardTemplate> kMockRewardTemplates = [
  RewardTemplate(
    title: 'Membership discount',
    subtitle: '% off or \$ discount',
    imageAsset: 'assets/images/reward_membership_discount.png',
  ),
  RewardTemplate(
    title: 'Gym branded gear',
    subtitle: 'Apparel or equipment',
    imageAsset: 'assets/images/reward_gym_tshirt.png',
  ),
  RewardTemplate(
    title: 'Film and review session',
    subtitle: 'Recorded rounds + coach notes',
    imageAsset: 'assets/images/reward_film_review.png',
  ),
  RewardTemplate(
    title: 'Custom',
    subtitle: 'Anything you want',
    imageAsset: 'assets/images/reward_custom.png',
  ),
];

const List<PendingRedemption> kMockPendingRedemptions = [
  PendingRedemption(
    memberName: 'Amy Traver',
    rewardTitle: 'Hand wraps',
    priceLabel: '30% off',
    pointsCost: 1500,
    imageAsset: 'assets/images/reward_hand_wraps.png',
    code: 'TXR-3K9P',
    requestedAt: 'Today, 6:12 PM',
  ),
  PendingRedemption(
    memberName: 'Justin Stemmons',
    rewardTitle: 'Private Training (15 min)',
    priceLabel: 'Free',
    pointsCost: 1800,
    imageAsset: 'assets/images/reward_private_training.png',
    code: 'QP7-M2L4',
    requestedAt: 'Today, 5:48 PM',
  ),
  PendingRedemption(
    memberName: 'Lily Altega',
    rewardTitle: 'Bring a friend',
    priceLabel: 'Free',
    pointsCost: 800,
    imageAsset: 'assets/images/reward_bring_friend.png',
    code: 'BF9-X1C8',
    requestedAt: 'Yesterday, 8:03 PM',
  ),
  PendingRedemption(
    memberName: 'Timothy Tom',
    rewardTitle: 'Boxing gloves',
    priceLabel: '10% off',
    pointsCost: 2500,
    imageAsset: 'assets/images/reward_boxing_gloves.png',
    code: 'GL2-7VK3',
    requestedAt: 'Yesterday, 7:21 PM',
  ),
];

/// One member's reward redemptions for the member-detail page — a mix of
/// pending (awaiting desk confirmation) and already-approved, shown together
/// in a single grid.
const List<PendingRedemption> kMockMemberRedemptions = [
  PendingRedemption(
    memberName: 'Justin Stemmons',
    rewardTitle: 'Private Training (15 min)',
    priceLabel: 'Free',
    pointsCost: 1800,
    imageAsset: 'assets/images/reward_private_training.png',
    code: 'QP7-M2L4',
    requestedAt: 'Today, 5:48 PM',
  ),
  PendingRedemption(
    memberName: 'Justin Stemmons',
    rewardTitle: 'Hand wraps',
    priceLabel: '30% off',
    pointsCost: 1500,
    imageAsset: 'assets/images/reward_hand_wraps.png',
    code: 'TXR-3K9P',
    requestedAt: 'Today, 6:12 PM',
  ),
  PendingRedemption(
    memberName: 'Justin Stemmons',
    rewardTitle: 'Bring a friend to a class',
    priceLabel: 'Free',
    pointsCost: 750,
    imageAsset: 'assets/images/reward_bring_friend.png',
    code: 'BF1-A7K2',
    requestedAt: 'Mar 2, 7:30 PM',
    approved: true,
  ),
  PendingRedemption(
    memberName: 'Justin Stemmons',
    rewardTitle: 'Gym t-shirt',
    priceLabel: 'Free',
    pointsCost: 1500,
    imageAsset: 'assets/images/reward_gym_tshirt.png',
    code: 'TS4-9QW1',
    requestedAt: 'Feb 24, 6:05 PM',
    approved: true,
  ),
  PendingRedemption(
    memberName: 'Justin Stemmons',
    rewardTitle: 'Boxing gloves',
    priceLabel: '10% off',
    pointsCost: 3000,
    imageAsset: 'assets/images/reward_boxing_gloves.png',
    code: 'GL8-2VK7',
    requestedAt: 'Feb 18, 8:40 PM',
    approved: true,
  ),
];
