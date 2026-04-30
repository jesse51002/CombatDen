import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/rewards/add_rewards_section.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/rewards/rewards_tier_section.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// "In app Rewards Store" — top-level card that bundles every points
/// tier together with the "Add more rewards" grid at the bottom.
class RewardsStoreCard extends StatelessWidget {
  final List<RewardItem> rewards;
  final List<RewardTemplate> addableRewards;

  const RewardsStoreCard({
    super.key,
    required this.rewards,
    required this.addableRewards,
  });

  @override
  Widget build(BuildContext context) {
    final tiers = _groupByPoints(rewards);

    return SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingBig,
        vertical: DesignConstants.paddingBig,
      ),
      child: Column(
        spacing: DesignConstants.spacingBig,
        children: [
          SizedBox(
            width: double.infinity,
            child: Text(
              'In app Rewards Store',
              style: DesignConstants.h1,
              textAlign: TextAlign.center,
            ),
          ),
          for (final tier in tiers)
            RewardsTierSection(
              points: tier.key,
              rewards: tier.value,
            ),
          AddRewardsSection(templates: addableRewards),
        ],
      ),
    );
  }

  /// Group rewards by points tier in ascending order.
  List<MapEntry<int, List<RewardItem>>> _groupByPoints(
    List<RewardItem> items,
  ) {
    final map = <int, List<RewardItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.points, () => []).add(item);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }
}
