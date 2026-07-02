import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/data/models/rank_full_response.dart';
import 'package:crm/features/memberships/presentation/dialogs/edit_rank_dialog.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_color.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';

/// One sub-rank row inside a group card: drag handle, colour swatch,
/// sub-rank name, the classes-to-advance threshold, edit + delete.
class RankLadderRow extends StatelessWidget {
  final RankFullResponse rank;
  final int subIndex;
  final RanksLoaded state;

  const RankLadderRow({
    super.key,
    required this.rank,
    required this.subIndex,
    required this.state,
  });

  Future<void> _delete(BuildContext context) async {
    final bloc = context.read<RanksBloc>();
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Delete ${rank.displayLabel}',
      message: 'Members on this rank move to a neighbouring rank. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed) return;
    bloc.add(RankDeleted(rankId: rank.rankId, gymId: state.gymId));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingTiny,
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          ReorderableDragStartListener(
            index: subIndex,
            child: Icon(
              Symbols.drag_indicator_sharp,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.text3rd,
              weight: DesignConstants.iconWeight,
            ),
          ),
          RankColorSwatch(color: rank.color),
          Expanded(child: Text(rank.subName, style: DesignConstants.p)),
          Text(
            '${rank.classesTillRankup} classes',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          IconButton(
            icon: Icon(
              Symbols.edit_sharp,
              size: DesignConstants.iconSizeSmall,
              weight: DesignConstants.iconWeight,
            ),
            onPressed: () => EditRankDialog.showEdit(
              context: context,
              bloc: context.read<RanksBloc>(),
              gymId: state.gymId,
              rank: rank,
            ),
          ),
          IconButton(
            icon: Icon(
              Symbols.delete_sharp,
              size: DesignConstants.iconSizeSmall,
              color: DesignConstants.badRed,
              weight: DesignConstants.iconWeight,
            ),
            onPressed: () => _delete(context),
          ),
        ],
      ),
    );
  }
}
