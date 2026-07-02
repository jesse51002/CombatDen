import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';

/// The gym's rank-system on/off toggle. Enabling backfills every
/// rank-less member to the lowest rank, so it asks first.
class RankEnabledSection extends StatelessWidget {
  final RanksLoaded state;

  const RankEnabledSection({super.key, required this.state});

  Future<void> _onChanged(BuildContext context, bool value) async {
    final bloc = context.read<RanksBloc>();
    if (value) {
      final message = state.ranks.isEmpty
          ? 'Your ladder is empty. Add at least one rank before '
              'enabling, or every member stays unranked.'
          : 'Enabling ranks assigns every unranked member to your '
              'lowest rank (${state.ranks.first.displayLabel}). '
              'This cannot be undone.';
      final confirmed = await ConfirmationModal.show(
        context: context,
        title: 'Enable rank system',
        message: message,
        confirmLabel: 'Enable',
      );
      if (!confirmed) return;
    }
    bloc.add(RankEnabledToggled(gymId: state.gymId, isEnabled: value));
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingSmall),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text('Rank system', style: DesignConstants.h2),
                  Text(
                    'When on, members show a rank and earn progress '
                    'toward the next one.',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: state.isRankEnabled,
              onChanged: state.isMutating
                  ? null
                  : (v) => _onChanged(context, v),
            ),
          ],
        ),
      ),
    );
  }
}
