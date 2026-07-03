import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/rewards/bloc/rewards_bloc.dart';
import 'package:crm/features/rewards/bloc/rewards_state.dart';
import 'package:crm/features/rewards/presentation/widgets/live_redemption_card.dart';
import 'package:crm/shared/widgets/fill_grid.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// The Loyalty tab's "Pending Redemption Approval" section.
///
/// **Admin path** (`gymId != null`): reads from [RewardsBloc] — real
/// pending redemptions with Approve + Reject actions.
///
/// **Template path** (`gymId == null`): hidden (pending redemptions are
/// per-member data that requires a real gym; the template preview has none).
class PendingApprovalSection extends StatelessWidget {
  const PendingApprovalSection({super.key});

  @override
  Widget build(BuildContext context) {
    final gymId = selectedGym.gymId;
    if (gymId == null) return const SizedBox.shrink();
    return const _LivePendingSection();
  }
}

class _LivePendingSection extends StatelessWidget {
  const _LivePendingSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RewardsBloc, RewardsState>(
      builder: (context, state) {
        // Hide section while loading and when empty.
        if (state.pendingStatus == RewardsPendingStatus.initial ||
            state.pendingStatus == RewardsPendingStatus.loading) {
          return const SizedBox.shrink();
        }
        if (state.pendingItems.isEmpty) return const SizedBox.shrink();

        return SubtitleSection(
          title: 'Pending Redemption Approval',
          child: FillGrid(
            minItemWidth: 260,
            children: [
              for (final item in state.pendingItems)
                LiveRedemptionCard(item: item),
            ],
          ),
        );
      },
    );
  }
}
