import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/add_reward_section.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/pending_approval_section.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/rewards_grid_section.dart';
import 'package:crm/features/rewards/bloc/rewards_bloc.dart';
import 'package:crm/features/rewards/bloc/rewards_event.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';

/// Loyalty tab: the points-based rewards store, an "add your own" grid,
/// and the queue of redemptions awaiting desk confirmation.
///
/// Provides a [RewardsBloc] scoped to this tab's lifetime and immediately
/// triggers a load when a real gym is active (`selectedGym.gymId != null`).
/// In template-preview mode (`gymId == null`) no bloc is needed — the sub-
/// widgets fall back to [selectedGym.detail] for display-only content.
class LoyaltyTab extends StatelessWidget {
  const LoyaltyTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Template preview path: no real gym, no bloc.
    // sub-widgets branch on gymId themselves.
    if (selectedGym.gymId == null) {
      return const _LoyaltyTabContent();
    }

    return RepositoryProvider<RewardsRepository>(
      create: (_) => RewardsRepository(apiClient: ApiClient()),
      child: BlocProvider<RewardsBloc>(
        create: (ctx) => RewardsBloc(
          repository: ctx.read<RewardsRepository>(),
        )..add(const RewardsLoadRequested()),
        child: const _LoyaltyTabContent(),
      ),
    );
  }
}

class _LoyaltyTabContent extends StatelessWidget {
  const _LoyaltyTabContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: const [
        PendingApprovalSection(),
        RewardsGridSection(),
        AddRewardSection(),
      ],
    );
  }
}
