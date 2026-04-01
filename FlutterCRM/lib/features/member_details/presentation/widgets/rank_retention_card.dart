import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/retention_thresholds.dart';
import 'package:crm/features/member_details/data/models/rank_retention.dart';
import 'package:crm/features/member_details/data/models/reward_card_model.dart';
import 'package:crm/features/member_details/presentation/widgets/retention_stat_item.dart';
import 'package:crm/features/member_details/presentation/widgets/reward_card.dart';
import 'package:crm/shared/widgets/outlined_action_button.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Card displaying rank progression, retention stats,
/// and recently redeemed rewards.
class RankRetentionCard extends StatelessWidget {
  final RankRetention rankRetention;
  final List<RewardCardModel> rewards;

  const RankRetentionCard({
    super.key,
    required this.rankRetention,
    required this.rewards,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Rank & Retention',
      children: [
        _RankDisplay(rankRetention: rankRetention),
        const SizedBox(
          height: DesignConstants.spacingMedium,
        ),
        OutlinedActionButton(
          label: 'Promote',
          onPressed: () {
            // TODO: Open promotion flow
          },
        ),
        const SizedBox(
          height: DesignConstants.spacingLarge,
        ),
        // Retention subsection
        Text('Retention', style: DesignConstants.h3),
        const SizedBox(
          height: DesignConstants.spacingMedium,
        ),
        _RetentionGrid(rankRetention: rankRetention),
        // Recently Redeemed Rewards
        if (rewards.isNotEmpty) ...[
          const SizedBox(
            height:
                DesignConstants.spacingLarge,
          ),
          Text(
            'Recently Redeemed Rewards',
            style: DesignConstants.h3,
          ),
          const SizedBox(
            height:
                DesignConstants.spacingMedium,
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: rewards
                  .map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(
                        right: DesignConstants
                            .spacingMedium
                            ,
                      ),
                      child: RewardCard(reward: r),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _RankDisplay extends StatelessWidget {
  final RankRetention rankRetention;

  const _RankDisplay({required this.rankRetention});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            // Rank badge image
            Semantics(
              label:
                  'Current rank: ${rankRetention.rankName ?? 'Unknown'}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  DesignConstants.spacingSmall,
                ),
                child: SizedBox(
                  width: 80.0,
                  height: 80.0,
                  child: rankRetention.rankImageUrl != null
                      ? Image.network(
                          rankRetention.rankImageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              _rankPlaceholder(),
                        )
                      : _rankPlaceholder(),
                ),
              ),
            ),
            const SizedBox(
              width:
                  DesignConstants.spacingMedium,
            ),
            // Rank stats
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _statRow(
                    Icons.person,
                    '${rankRetention.classesInRank} classes',
                    'Classes in Rank',
                  ),
                  const SizedBox(
                    height: DesignConstants.spacingSmall
                        ,
                  ),
                  if (rankRetention.recommendPromoIn !=
                      null)
                    _statRow(
                      Icons.trending_up,
                      'In ${rankRetention.recommendPromoIn} classes',
                      'Recommend Promo',
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(
          height: DesignConstants.spacingSmall,
        ),
        // Rank name
        if (rankRetention.rankName != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              rankRetention.rankName!,
              style: DesignConstants.h3,
            ),
          ),
      ],
    );
  }

  Widget _statRow(
    IconData icon,
    String value,
    String label,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: DesignConstants.text2nd,
        ),
        const SizedBox(
          width: DesignConstants.spacingSmall,
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: DesignConstants.p.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: ' / $label',
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _rankPlaceholder() {
    return Container(
      color: DesignConstants.cardBackground,
      child: const Center(
        child: Icon(
          Icons.military_tech,
          color: DesignConstants.text,
          size: 40,
        ),
      ),
    );
  }
}

class _RetentionGrid extends StatelessWidget {
  final RankRetention rankRetention;

  const _RetentionGrid({required this.rankRetention});

  @override
  Widget build(BuildContext context) {
    final daysSince =
        rankRetention.daysSinceLastClass;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: RetentionStatItem(
                icon: Icons.access_time,
                value: daysSince != null
                    ? '$daysSince days ago'
                    : 'Unknown',
                label: 'Last Class',
                valueColor: daysSince != null
                    ? RetentionThreshold
                        .getLastClassColor(daysSince)
                    : DesignConstants.text2nd,
              ),
            ),
            const SizedBox(
              width:
                  DesignConstants.spacingMedium,
            ),
            Expanded(
              child: RetentionStatItem(
                icon: Icons.bolt,
                value:
                    '${rankRetention.classStreakWeeks} weeks',
                label: 'Class Streak',
                valueColor:
                    RetentionThreshold.getStreakColor(
                  rankRetention.classStreakWeeks,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(
          height: DesignConstants.spacingMedium,
        ),
        Row(
          children: [
            Expanded(
              child: RetentionStatItem(
                icon: Icons.star,
                value:
                    '${rankRetention.pointsBalance} points',
                label: 'Points Balance',
                valueColor: DesignConstants.text,
              ),
            ),
            const SizedBox(
              width:
                  DesignConstants.spacingMedium,
            ),
            Expanded(
              child: RetentionStatItem(
                icon: Icons.play_arrow,
                value:
                    '${rankRetention.videosWatched} videos',
                label: 'Videos Watched',
                valueColor: DesignConstants.text,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
