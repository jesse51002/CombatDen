import 'package:flutter/material.dart';

import 'package:crm/features/members/data/mock_loyalty.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/add_reward_card.dart';
import 'package:crm/shared/widgets/fill_grid.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// "Add your own" section: a grid of reward starters the admin can add
/// to the store.
class AddRewardSection extends StatelessWidget {
  const AddRewardSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Add your own',
      child: FillGrid(
        minItemWidth: 260,
        children: [
          for (final template in kMockRewardTemplates)
            AddRewardCard(template: template),
        ],
      ),
    );
  }
}
