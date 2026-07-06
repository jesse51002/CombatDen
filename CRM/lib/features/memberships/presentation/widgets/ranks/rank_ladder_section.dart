import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/data/models/rank_reorder_item.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/main_rank_card.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/sub_rank_strip.dart';
import 'package:crm/shared/widgets/warning_message.dart';

/// The gym's rank ladder — a vertical, MAIN-rank-only reorderable list.
/// Sub-ranks are no longer rows; each main rank is a prominent card with
/// its sub-positions shown as a strip beneath it. A drag reorders the
/// main ranks and dispatches one [RanksReordered] with the full new
/// main-order (sub-positions carry no order of their own now).
class RankLadderSection extends StatelessWidget {
  final RanksLoaded state;

  const RankLadderSection({super.key, required this.state});

  void _onReorder(BuildContext context, int oldIndex, int newIndex) {
    // `onReorderItem` already adjusts newIndex for the removed item at
    // oldIndex, so no off-by-one correction is needed.
    final reordered = [...state.ranks];
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    context.read<RanksBloc>().add(RanksReordered(
          gymId: state.gymId,
          ranks: [
            for (var i = 0; i < reordered.length; i++)
              RankReorderItem(
                rankId: reordered[i].rankId,
                mainRankNumOrder: i,
              ),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (state.ranks.isEmpty) {
      return const WarningMessage(
        message: 'No ranks yet. Use "Add New Rank" above to create the '
            'first one, or seed a preset below.',
      );
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) =>
          _onReorder(context, oldIndex, newIndex),
      children: [
        for (var i = 0; i < state.ranks.length; i++)
          Padding(
            key: ValueKey(state.ranks[i].rankId),
            padding: const EdgeInsets.only(
              bottom: DesignConstants.spacingLarge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingLarge,
              children: [
                MainRankCard(
                  rank: state.ranks[i],
                  gymId: state.gymId,
                  index: i,
                  isTop: i == state.ranks.length - 1,
                ),
                if (state.ranks[i].subRankCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: DesignConstants.paddingSmall,
                    ),
                    child: SubRankStrip(
                      rank: state.ranks[i],
                      subRankType: state.subRankType,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
