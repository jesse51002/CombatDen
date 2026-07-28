import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout_data.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_topbar.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/points_headline.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card_data.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_store_card.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs.dart';

/// `RewardsFormat.posterDeck` — one reward at a time.
///
/// Topbar, segmented tabs and the points headline pin to the top; the
/// rest of the screen is a horizontally snapping deck of posters, each
/// taking the full width. Fewest rewards visible at once, strongest
/// individual reward.
///
/// **The redeem action stays on the poster.** The proposal pinned ONE
/// action under the deck to serve whichever poster was focused. Two
/// things argue against it and the code follows the code: a card that
/// does not carry its own action breaks the one contract every reward
/// card holds, and a button outside the deck is genuinely ambiguous
/// mid-swipe — halfway between two posters it belongs to neither. Same
/// element count per reward AND per screen, no bespoke counting rule in
/// the invariant gate.
class RewardsPosterDeck extends StatelessWidget {
  const RewardsPosterDeck({super.key, required this.data});

  final RewardsLayoutData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        RewardsTopbar(data: data),
        RewardsTabs(
          active: RewardsTab.pointsStore,
          layout: RewardsTabsLayout.segmented,
          onMyRewardsTap: data.onMyRewardsTap,
        ),
        PointsHeadline(points: data.totalPoints),
        if (data.hasStatus)
          RewardsLoadStatus(data.statusMessage)
        else
          Expanded(child: _PosterDeck(items: data.rewards)),
      ],
    );
  }
}

/// The snapping deck. Every poster is built up front — a lazy viewport
/// would leave most of the store unmounted, which is exactly the kind
/// of quiet disappearance the invariant gate exists to catch.
class _PosterDeck extends StatelessWidget {
  const _PosterDeck({required this.items});

  final List<Reward> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const PageScrollPhysics(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              SizedBox(
                width: constraints.maxWidth,
                child: Padding(
                  // The page's own gutter, not a gap between pages.
                  padding: EdgeInsets.symmetric(
                    horizontal: DesignConstants.screenHorizontalPadding,
                  ),
                  child: RewardStoreCard(
                    reward: item,
                    layout: RewardCardLayout.poster,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
