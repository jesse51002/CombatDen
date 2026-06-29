import 'package:flutter/material.dart';

import 'package:crm/showcase/rewards/mock_points_store.dart';
import 'package:crm/showcase/rewards/points_headline.dart';
import 'package:crm/showcase/rewards/rewards_tabs.dart';
import 'package:crm/showcase/rewards/store_grid.dart';
import 'package:crm/showcase/showcase_content.dart';
import 'package:crm/showcase/showcase_tokens.dart';
import 'package:crm/showcase/support/showcase_bottom_nav.dart';
import 'package:crm/showcase/support/showcase_scaffold.dart';
import 'package:crm/showcase/support/showcase_topbar.dart';

/// Exact visual clone of the member app's **Points Store** (`PointsStoreScreen`):
/// the Points Store / My Rewards tabs, the sparkle "YOU EARNED — POINTS" hero
/// (your points balance), and the two-column store of redeemable items.
/// Static, non-scrolling surface; [loop] / [onCycleComplete] accepted for the
/// uniform API but unused. [gymName] / [gymLogo] are the host's gym identity.
/// When [rewards] is non-null, the store renders the selected gym's real
/// rewards instead of the bundled sample items (the points/streak chrome stays
/// sample — that's per-member, not gym data).
class RewardsShowcase extends StatelessWidget {
  const RewardsShowcase({
    super.key,
    this.loop = true,
    this.onCycleComplete,
    this.gymName = 'Your Gym',
    this.gymLogo,
    this.rewards,
  });

  final bool loop;
  final VoidCallback? onCycleComplete;
  final String gymName;
  final ImageProvider? gymLogo;
  final List<ShowcaseReward>? rewards;

  @override
  Widget build(BuildContext context) {
    const data = showcasePointsStoreData;
    final items = (rewards != null && rewards!.isNotEmpty)
        ? [
            for (final r in rewards!)
              ShowcasePointsStoreItem(
                title: r.title,
                priceLabel: r.priceLabel,
                pointsCost: r.pointsCost,
                imageUrl: r.imageUrl,
              ),
          ]
        : data.items;
    return ShowcaseScaffold(
      horizontalPadding: ShowcasePadding.none,
      bottomNav: const ShowcaseBottomNav(selected: ShowcaseNavTab.reward),
      // Lay the static store out at its natural height (top-aligned) and clip
      // anything past the screen — no scrolling, no overflow error.
      child: ClipRect(
        child: OverflowBox(
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: ShowcaseTokens.spacingBig,
            children: [
              ShowcaseTopbar(
                mode: ShowcaseTopbarMode.nameOnly,
                gymName: gymName,
                logoImage: gymLogo,
                streakDays: data.streakDays,
                pointsLabel: data.pointsLabel,
                rankBadgeAsset: data.rankBadgeAsset,
              ),
              const RewardsTabs(active: RewardsTab.pointsStore),
              PointsHeadline(points: data.totalPoints),
              StoreGrid(items: items),
            ],
          ),
        ),
      ),
    );
  }
}
