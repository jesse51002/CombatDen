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
class RewardSlide {
  const RewardSlide({
    required this.image,
    required this.name,
    required this.discountLabel,
    required this.pointsCost,
  });

  final ImageProvider image;
  final String name;
  final String discountLabel;
  final int pointsCost;

  /// A live reward from the member portal catalog
  /// (`GET /api/v1/member/gyms/{gid}/members/{mid}/rewards`) — network image.
  factory RewardSlide.fromRewardItem(RewardItem item) => RewardSlide(
        image: CachedNetworkImageProvider(item.imageUrl),
        name: item.title,
        discountLabel: item.priceLabel,
        pointsCost: item.pointCost,
      );

  /// A live reward from `GET /gyms/{gymId}` — image is a network URL.
  factory RewardSlide.fromReward(Reward reward) => RewardSlide(
        image: CachedNetworkImageProvider(reward.imageUrl),
        name: reward.title,
        discountLabel: reward.priceLabel,
        pointsCost: reward.pointsCost,
      );

  /// The bundled CombatDen fallback — image is a local asset.
  factory RewardSlide.fromMock(MockRewardItem item) => RewardSlide(
        image: ApiImage.rewardAsset(item.imageAsset),
        name: item.name,
        discountLabel: item.discountLabel,
        pointsCost: item.pointsCost,
      );
}
