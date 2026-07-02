import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_group.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_group_card.dart';
import 'package:crm/shared/widgets/warning_message.dart';

/// The gym's rank ladder as nested, indented, draggable groups. The
/// section owns reorder maths: a group drag or a sub drag rebuilds
/// the full ordering and dispatches one [RanksReordered].
class RankLadderSection extends StatelessWidget {
  final RanksLoaded state;

  const RankLadderSection({super.key, required this.state});

  void _dispatch(BuildContext context, List<RankGroup> groups) {
    context.read<RanksBloc>().add(RanksReordered(
          gymId: state.gymId,
          ranks: flattenToReorderItems(groups),
        ));
  }

  void _onGroupReorder(
    BuildContext context,
    List<RankGroup> groups,
    int oldIndex,
    int newIndex,
  ) {
    _dispatch(context, reorderIndex(groups, oldIndex, newIndex));
  }

  void _onSubReorder(
    BuildContext context,
    List<RankGroup> groups,
    int groupIndex,
    int oldIndex,
    int newIndex,
  ) {
    final group = groups[groupIndex];
    final next = [...groups];
    next[groupIndex] = RankGroup(
      mainOrder: group.mainOrder,
      mainName: group.mainName,
      subs: reorderIndex(group.subs, oldIndex, newIndex),
    );
    _dispatch(context, next);
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupRanks(state.ranks);
    if (groups.isEmpty) {
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
          _onGroupReorder(context, groups, oldIndex, newIndex),
      children: [
        for (var gi = 0; gi < groups.length; gi++)
          RankGroupCard(
            key: ValueKey('group-${groups[gi].mainName}-${groups[gi].mainOrder}'),
            group: groups[gi],
            groupIndex: gi,
            state: state,
            onSubReorder: (oldIndex, newIndex) =>
                _onSubReorder(context, groups, gi, oldIndex, newIndex),
          ),
      ],
    );
  }
}
