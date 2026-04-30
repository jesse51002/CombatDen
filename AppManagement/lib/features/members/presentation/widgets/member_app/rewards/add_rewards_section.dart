import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/rewards/add_reward_card.dart';

/// "Add more rewards" — a 2x2 grid of reward templates the admin can
/// drop into the store.
class AddRewardsSection extends StatelessWidget {
  final List<RewardTemplate> templates;

  const AddRewardsSection({super.key, required this.templates});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingBig,
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(
            'Add more rewards',
            style: DesignConstants.h1,
            textAlign: TextAlign.center,
          ),
        ),
        _Grid(templates: templates),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  final List<RewardTemplate> templates;

  const _Grid({required this.templates});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < templates.length; i += 2) {
      final left = templates[i];
      final right = i + 1 < templates.length ? templates[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            Expanded(child: AddRewardCard(template: left)),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : AddRewardCard(template: right),
            ),
          ],
        ),
      );
    }
    return Column(
      spacing: DesignConstants.spacingBig,
      children: rows,
    );
  }
}
