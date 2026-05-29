/// Hardcoded data for the Member App "Loyalty Program" tab.
///
/// The points-based **rewards store** is now live — driven by the selected
/// gym's rewards from the VideoService (see `RewardsGridSection` /
/// `gym_detail.dart`). What stays mock here is the per-member flow the gym
/// file can't carry: the redemption queue awaiting desk confirmation and the
/// "add your own" starter templates.
library;

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

  /// Bundled image (member-history mocks). Ignored when [imageUrl] is set.
  final String? imageAsset;

  /// Network image url — set when the redemption is built from a live gym
  /// reward (the loyalty-tab pending queue), so the card matches the store.
  final String? imageUrl;

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
    this.imageAsset,
    this.imageUrl,
    required this.code,
    required this.requestedAt,
    this.approved = false,
  });
}

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
