import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/presentation/dialogs/edit_rank_dialog.dart';
import 'package:crm/features/memberships/presentation/dialogs/rename_group_dialog.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_group.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_ladder_row.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';

/// A main-rank group card: a draggable header (reorders groups) with
/// rename / add-sub / delete actions, over an inner draggable list of
/// its sub-ranks (reorders within the group).
class RankGroupCard extends StatelessWidget {
  final RankGroup group;
  final int groupIndex;
  final RanksLoaded state;
  final void Function(int oldIndex, int newIndex) onSubReorder;

  const RankGroupCard({
    super.key,
    required this.group,
    required this.groupIndex,
    required this.state,
    required this.onSubReorder,
  });

  int get _nextSubOrder => group.subs.isEmpty
      ? 0
      : group.subs
              .map((s) => s.subRankNumOrder)
              .reduce((a, b) => a > b ? a : b) +
          1;

  Future<void> _deleteGroup(BuildContext context) async {
    final bloc = context.read<RanksBloc>();
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Delete ${group.mainName}',
      message: 'This deletes all ${group.subs.length} sub-rank(s) in '
          '${group.mainName}. Members on them move to a neighbouring '
          'rank. This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed) return;
    bloc.add(RankGroupDeleted(
      gymId: state.gymId,
      mainRankNumOrder: group.mainOrder,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignConstants.spacingMedium),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
          boxShadow: DesignConstants.cardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignConstants.paddingSmall),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              _header(context),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: onSubReorder,
                children: [
                  for (var si = 0; si < group.subs.length; si++)
                    RankLadderRow(
                      key: ValueKey(group.subs[si].rankId),
                      rank: group.subs[si],
                      subIndex: si,
                      state: state,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingSmall,
      children: [
        ReorderableDragStartListener(
          index: groupIndex,
          child: Icon(
            Symbols.drag_indicator_sharp,
            size: DesignConstants.iconSizeMedium,
            color: DesignConstants.text2nd,
            weight: DesignConstants.iconWeight,
          ),
        ),
        Expanded(child: Text(group.mainName, style: DesignConstants.h2)),
        IconButton(
          tooltip: 'Add sub-rank',
          icon: Icon(
            Symbols.add_sharp,
            size: DesignConstants.iconSizeSmall,
            weight: DesignConstants.iconWeight,
          ),
          onPressed: () => EditRankDialog.showAddToGroup(
            context: context,
            bloc: context.read<RanksBloc>(),
            gymId: state.gymId,
            mainOrder: group.mainOrder,
            mainName: group.mainName,
            nextSubOrder: _nextSubOrder,
          ),
        ),
        IconButton(
          tooltip: 'Rename group',
          icon: Icon(
            Symbols.edit_sharp,
            size: DesignConstants.iconSizeSmall,
            weight: DesignConstants.iconWeight,
          ),
          onPressed: () => RenameGroupDialog.show(
            context: context,
            bloc: context.read<RanksBloc>(),
            gymId: state.gymId,
            currentName: group.mainName,
            mainRankNumOrder: group.mainOrder,
          ),
        ),
        IconButton(
          tooltip: 'Delete group',
          icon: Icon(
            Symbols.delete_sharp,
            size: DesignConstants.iconSizeSmall,
            color: DesignConstants.badRed,
            weight: DesignConstants.iconWeight,
          ),
          onPressed: () => _deleteGroup(context),
        ),
      ],
    );
  }
}
