/// Hardcoded data for the Member App "Loyalty Program" tab.
///
/// The points-based **rewards store** is now live — driven by the selected
/// gym's rewards from the VideoService (see `RewardsGridSection` /
/// `gym_detail.dart`). What stays mock here is the per-member flow the gym
/// file can't carry: the redemption queue awaiting desk confirmation and the
/// "add your own" starter templates.
library;

/// A starter the admin can add to their store from the "Add your own"
/// grid. Clicking one opens the reward create form pre-filled with
/// [title], [suggestedPointCost], and [suggestedPriceLabel].
/// The image is never pre-filled — the admin must upload one.
class RewardTemplate {
  final String title;
  final String? subtitle;
  final String imageAsset;

  /// Suggested starting value for the point-cost field.
  final int? suggestedPointCost;

  /// Suggested badge label (e.g. 'Free', '30% off').
  final String? suggestedPriceLabel;

  const RewardTemplate({
    required this.title,
    this.subtitle,
    required this.imageAsset,
    this.suggestedPointCost,
    this.suggestedPriceLabel,
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
    suggestedPointCost: 2500,
    suggestedPriceLabel: '30% off',
  ),
  RewardTemplate(
    title: 'Gym branded gear',
    subtitle: 'Apparel or equipment',
    imageAsset: 'assets/images/reward_gym_tshirt.png',
    suggestedPointCost: 1500,
    suggestedPriceLabel: 'Free',
  ),
  RewardTemplate(
    title: 'Film and review session',
    subtitle: 'Recorded rounds + coach notes',
    imageAsset: 'assets/images/reward_film_review.png',
    suggestedPointCost: 2000,
    suggestedPriceLabel: 'Free',
  ),
  RewardTemplate(
    title: 'Custom',
    subtitle: 'Anything you want',
    imageAsset: 'assets/images/reward_custom.png',
  ),
];
