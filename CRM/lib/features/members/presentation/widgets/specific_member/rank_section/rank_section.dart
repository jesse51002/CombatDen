import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/data/mock_member_history.dart';
import 'package:crm/features/members/presentation/widgets/specific_member/rank_section/icon_stat_tile.dart';
import 'package:crm/features/members/presentation/widgets/specific_member/rank_section/rank_display.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Rank block: belt icon + label on the left, two stat tiles on the
/// right, full-width "Promote" button underneath.
class RankSection extends StatelessWidget {
  final DemoMember member;
  final MemberDetailStats stats;

  const RankSection({
    super.key,
    required this.member,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        _RankGrid(member: member, stats: stats),
        AppOutlineButton(
          text: 'Promote',
          fullWidth: true,
          onPressed: () => debugPrint('TODO: promote member'),
        ),
      ],
    );
  }
}

class _RankGrid extends StatelessWidget {
  final DemoMember member;
  final MemberDetailStats stats;

  const _RankGrid({required this.member, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        Expanded(child: RankDisplay(member: member)),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: DesignConstants.spacingBig,
            children: [
              IconStatTile(
                icon: Symbols.workspace_premium_sharp,
                value: '${stats.classesInRank} classes',
                caption: 'Classes In Rank',
              ),
              IconStatTile(
                icon: Symbols.trending_up_sharp,
                value: 'In ${stats.classesUntilPromo} classes',
                caption: 'Recommend Promo',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
