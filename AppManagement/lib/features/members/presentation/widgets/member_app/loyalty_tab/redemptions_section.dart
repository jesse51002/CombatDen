import 'package:flutter/material.dart';

import 'package:app_management/features/members/data/mock_loyalty.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/redemption_card.dart';
import 'package:app_management/shared/widgets/fill_grid.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// A grid of reward redemptions, shown as visual cards so staff recognize the
/// reward art. Pending ones offer Review & confirm; approved ones show an
/// "Approved" marker. Defaults to the member-app's pending queue; pass
/// [redemptions] + [title] to reuse it elsewhere (e.g. one member's history).
class RedemptionsSection extends StatelessWidget {
  final List<PendingRedemption> redemptions;
  final String title;

  const RedemptionsSection({
    super.key,
    this.redemptions = kMockPendingRedemptions,
    this.title = 'Pending Redemption Approval',
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: title,
      child: FillGrid(
        minItemWidth: 240,
        children: [
          for (final r in redemptions) RedemptionCard(redemption: r),
        ],
      ),
    );
  }
}
