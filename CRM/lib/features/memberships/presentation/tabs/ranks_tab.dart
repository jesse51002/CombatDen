import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/memberships/presentation/dialogs/preset_seed_dialog.dart';
import 'package:crm/features/memberships/presentation/widgets/memberships_tab_scaffold.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_enabled_section.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_ladder_section.dart';

/// Ranks tab of the Gym screen — the rank-system toggle, the nested
/// draggable rank ladder, and a seed-from-preset affordance.
class RanksTab extends StatelessWidget {
  const RanksTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RanksBloc, RanksState>(
      listenWhen: (prev, curr) =>
          curr is RanksLoaded && curr.actionError != null,
      listener: (context, state) {
        if (state is RanksLoaded && state.actionError != null) {
          showTabActionError(context, state.actionError!);
        }
      },
      builder: (context, state) {
        return switch (state) {
          RanksInitial() || RanksLoading() => const TabLoading(),
          RanksError() => TabError(
              message: state.message,
              onRetry: () => context
                  .read<RanksBloc>()
                  .add(RanksInitRequested(state.gymId)),
            ),
          RanksLoaded() => _RanksBody(state: state),
        };
      },
    );
  }
}

class _RanksBody extends StatelessWidget {
  final RanksLoaded state;

  const _RanksBody({required this.state});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: DesignConstants.paddingBig),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.screenHorizontalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
            RankEnabledSection(state: state),
            RankLadderSection(state: state),
            Center(
              child: TextButton(
                onPressed: () => PresetSeedDialog.show(
                  context: context,
                  bloc: context.read<RanksBloc>(),
                  repository: context.read<RanksRepository>(),
                  gymId: state.gymId,
                  hasExistingRanks: state.ranks.isNotEmpty,
                ),
                child: Text(
                  'Seed from preset',
                  style: DesignConstants.h3.copyWith(
                    color: DesignConstants.primaryColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
