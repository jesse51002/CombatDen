import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/data/mock_member_history.dart';
import 'package:crm/features/members/presentation/widgets/specific_member/rank_section/icon_stat_tile.dart';

/// 2x2 retention/engagement grid:
///   Last Class (green) | Class Streak (green)
///   Points Balance     | Videos Watched
class RetentionSection extends StatelessWidget {
  final MemberDetailStats stats;

  const RetentionSection({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingBig,
      children: [
        Row(
          spacing: DesignConstants.spacingBig,
          children: [
            Expanded(child: _LastClassTile(stats: stats)),
            Expanded(child: _StreakTile(stats: stats)),
          ],
        ),
        Row(
          spacing: DesignConstants.spacingBig,
          children: [
            Expanded(child: _PointsTile(stats: stats)),
            Expanded(child: _VideosTile(stats: stats)),
          ],
        ),
      ],
    );
  }
}

class _LastClassTile extends StatelessWidget {
  final MemberDetailStats stats;
  const _LastClassTile({required this.stats});

  @override
  Widget build(BuildContext context) {
    return IconStatTile(
      icon: Symbols.schedule_sharp,
      iconSize: DesignConstants.iconSizeBig,
      value: '${stats.lastClassDaysAgo} days ago',
      caption: 'Last Class',
      valueColor: DesignConstants.goodGreen,
    );
  }
}

class _StreakTile extends StatelessWidget {
  final MemberDetailStats stats;
  const _StreakTile({required this.stats});

  @override
  Widget build(BuildContext context) {
    return IconStatTile(
      icon: Symbols.bolt_sharp,
      iconSize: DesignConstants.iconSizeBig,
      value: '${stats.classStreakWeeks} weeks',
      caption: 'Class Streak',
      valueColor: DesignConstants.goodGreen,
    );
  }
}

class _PointsTile extends StatelessWidget {
  final MemberDetailStats stats;
  const _PointsTile({required this.stats});

  @override
  Widget build(BuildContext context) {
    return IconStatTile(
      icon: Symbols.star_sharp,
      iconSize: DesignConstants.iconSizeBig,
      value: '${stats.pointsBalance} points',
      caption: 'Points Balance',
    );
  }
}

class _VideosTile extends StatelessWidget {
  final MemberDetailStats stats;
  const _VideosTile({required this.stats});

  @override
  Widget build(BuildContext context) {
    return IconStatTile(
      icon: Symbols.play_arrow_sharp,
      iconSize: DesignConstants.iconSizeBig,
      value: '${stats.videosWatched} videos',
      caption: 'Videos Watched',
    );
  }
}
