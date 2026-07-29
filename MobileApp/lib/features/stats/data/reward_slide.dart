import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_app/features/rewards/data/models/reward_item.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';

/// One reward in the post-class Rewards carousel, source-agnostic.
///
/// Bridges the possible sources into a single render path: the member portal
/// catalog's live [RewardItem] (a network image), the VideoService [Reward]
/// (a network image), and the **bundled** fallback [MockRewardItem] (an
/// `assets/rewards/` image). Each factory resolves the right [ImageProvider]
/// so the carousel never branches on the source.
///
/// It is a pure data class — no `build` — so it lives in `data/` beside
/// `rewards_card_view.dart`, which decides each slide's affordance and must
/// not import from `presentation/`.
class RewardSlide {
  const RewardSlide({
    required this.image,
    required this.name,
    required this.discountLabel,
    required this.pointsCost,
    required this.isLive,
  });

  final ImageProvider image;
  final String name;
  final String discountLabel;
  final int pointsCost;

  /// Whether [pointsCost] is a REAL cost from this gym's catalog.
  ///
  /// False on the bundled fallback, whose costs are demo numbers (800 / 2,200
  /// / 3,500). Measuring a member's real balance against those would state a
  /// shortfall that doesn't exist, so a non-live slide always renders the
  /// UNKNOWN affordance — today's shipped look — whatever the balance is.
  final bool isLive;

  /// A live reward from the member portal catalog
  /// (`GET /api/v1/member/gyms/{gid}/members/{mid}/rewards`) — network image.
  factory RewardSlide.fromRewardItem(RewardItem item) => RewardSlide(
        image: CachedNetworkImageProvider(item.imageUrl),
        name: item.title,
        discountLabel: item.priceLabel,
        pointsCost: item.pointCost,
        isLive: true,
      );

  /// A live reward from `GET /gyms/{gymId}` — image is a network URL.
  factory RewardSlide.fromReward(Reward reward) => RewardSlide(
        image: CachedNetworkImageProvider(reward.imageUrl),
        name: reward.title,
        discountLabel: reward.priceLabel,
        pointsCost: reward.pointsCost,
        isLive: true,
      );

  /// The bundled CombatDen fallback — image is a local asset and the costs are
  /// demo numbers, so [isLive] is false.
  factory RewardSlide.fromMock(MockRewardItem item) => RewardSlide(
        image: ApiImage.rewardAsset(item.imageAsset),
        name: item.name,
        discountLabel: item.discountLabel,
        pointsCost: item.pointsCost,
        isLive: false,
      );
}
