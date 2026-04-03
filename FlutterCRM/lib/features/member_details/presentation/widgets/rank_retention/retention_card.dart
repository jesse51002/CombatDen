import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/retention_thresholds.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/models/reward_card_model.dart';
import 'package:crm/features/member_details/presentation/widgets/rank_retention/retention_stat_item.dart';
import 'package:crm/features/member_details/presentation/widgets/rank_retention/reward_card.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// Card displaying retention stats and recently
/// redeemed rewards.
class RetentionCard extends StatelessWidget {
  final Retention retention;
  final List<RewardCardModel> rewards;

  const RetentionCard({
    super.key,
    required this.retention,
    required this.rewards,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Retention',
      children: [
        SubtitleSection(
          title: 'Retention',
          child: _RetentionGrid(retention: retention),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            spacing: DesignConstants.spacingLarge,
            children: [
              Text(
                'Recently Redeemed Rewards',
                style: DesignConstants.h2,
              ),
              Expanded(
                child: rewards.isEmpty
                    ? Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color:
                              DesignConstants.card,
                          borderRadius:
                              BorderRadius.circular(
                            DesignConstants
                                .radiusSmall,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'No rewards claimed yet',
                            style: DesignConstants.h2
                                .copyWith(
                              color: DesignConstants
                                  .text2nd,
                            ),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection:
                            Axis.horizontal,
                        child: Row(
                          spacing: DesignConstants
                              .spacingMedium,
                          children: rewards
                              .map(
                                (r) => RewardCard(
                                  reward: r,
                                ),
                              )
                              .toList(),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RetentionGrid extends StatelessWidget {
  final Retention retention;

  const _RetentionGrid({required this.retention});

  @override
  Widget build(BuildContext context) {
    final daysSince = retention.daysSinceLastClass;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: RetentionStatItem(
                icon: Symbols.schedule_sharp,
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
                icon: Symbols.bolt_sharp,
                value:
                    '${retention.classStreakWeeks} weeks',
                label: 'Class Streak',
                valueColor:
                    RetentionThreshold.getStreakColor(
                  retention.classStreakWeeks,
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
                icon: Symbols.star_sharp,
                value:
                    '${retention.pointsBalance} points',
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
                icon: Symbols.play_arrow_sharp,
                value:
                    '${retention.videosWatched} videos',
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
