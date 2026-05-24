import 'package:flutter/material.dart';

import 'package:app_management/features/members/data/mock_loyalty.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/pending_approval_card.dart';
import 'package:app_management/shared/widgets/fill_grid.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// "Pending Redemption Approval" — members waiting for the admin to
/// confirm a reward at the desk, shown as a visual grid so staff
/// recognize the reward art. Tapping a card opens the confirm dialog.
class PendingApprovalSection extends StatelessWidget {
  const PendingApprovalSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Pending Redemption Approval',
      child: FillGrid(
        minItemWidth: 240,
        children: [
          for (final r in kMockPendingRedemptions)
            PendingApprovalCard(redemption: r),
        ],
      ),
    );
  }
}
