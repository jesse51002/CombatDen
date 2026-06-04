import 'package:flutter/material.dart';

import 'package:crm/features/members/data/mock_loyalty.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/redemption_card.dart';
import 'package:crm/shared/widgets/fill_grid.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// A grid of reward redemptions, shown as visual cards so staff recognize the
/// reward art. Pending ones offer Review & confirm; approved ones show an
/// "Approved" marker. Reused by the loyalty tab's live pending queue and by one
/// member's redemption history — both pass their own [redemptions] + [title].
class RedemptionsSection extends StatelessWidget {
  final List<PendingRedemption> redemptions;
  final String title;

  const RedemptionsSection({
    super.key,
    required this.redemptions,
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
