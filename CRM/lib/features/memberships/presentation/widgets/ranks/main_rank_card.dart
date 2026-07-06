import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// One main rank on the ladder — the PROMINENT half of the inversion: a
/// large belt, the rank name, its classes-to-next-belt threshold, and
/// reorder / edit / delete affordances. The whole card is tappable and
/// opens the rank's detail (its members + promotion).
///
/// The sub-rank strip is rendered separately, beneath this card, by
/// [RankLadderSection] — this card is the belt itself.
class MainRankCard extends StatelessWidget {
  final MainRank rank;
  final String gymId;

  /// Position in the ladder — drives the drag handle and the "top of the
  /// ladder" copy on the highest rank (which has no belt above it).
  final int index;
  final bool isTop;

  const MainRankCard({
    super.key,
    required this.rank,
    required this.gymId,
    required this.index,
    required this.isTop,
  });

  Future<void> _delete(BuildContext context) async {
    final bloc = context.read<RanksBloc>();
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Delete ${rank.name}',
      message: 'Members on this rank move to a neighbouring rank. Its '
          '${rank.subRankCount} sub-position(s) go with it. This cannot '
          'be undone.',
      confirmLabel: 'Delete',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed) return;
    bloc.add(RankDeleted(rankId: rank.rankId, gymId: gymId));
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context)
        .pushNamed(AppRoutes.membershipsRankDetailPath(rank.rankId));
  }

  Future<void> _edit(BuildContext context) async {
    final bloc = context.read<RanksBloc>();
    await Navigator.of(context).pushNamed(
      AppRoutes.membershipsRankEditor,
      arguments: rank,
    );
    // Repository-direct editor — reload the ladder on return so a saved
    // change shows (mirrors the plan / waiver editors).
    bloc.add(RanksInitRequested(gymId));
  }

  @override
  Widget build(BuildContext context) {
    final caption = isTop
        ? 'Top of the ladder'
        : '${rank.classesToNextMajor} classes to next rank';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _openDetail(context),
          borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
          child: Padding(
            padding: const EdgeInsets.all(DesignConstants.paddingSmall),
            child: Row(
              spacing: DesignConstants.spacingLarge,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Symbols.drag_indicator_sharp,
                    size: DesignConstants.iconSizeMedium,
                    color: DesignConstants.text3rd,
                    weight: DesignConstants.iconWeight,
                  ),
                ),
                RankBeltImage(
                  imageUrl: rank.imageUrl,
                  size: 76,
                  radius: DesignConstants.radiusBig,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: DesignConstants.spacingTiny,
                    children: [
                      Text(
                        rank.name,
                        style: DesignConstants.h1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        caption,
                        style: DesignConstants.pSmall.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit rank',
                  onPressed: () => _edit(context),
                  icon: Icon(
                    Symbols.edit_sharp,
                    size: DesignConstants.iconSizeMedium,
                    color: DesignConstants.text2nd,
                    weight: DesignConstants.iconWeight,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete rank',
                  onPressed: () => _delete(context),
                  icon: Icon(
                    Symbols.delete_sharp,
                    size: DesignConstants.iconSizeMedium,
                    color: DesignConstants.badRed,
                    weight: DesignConstants.iconWeight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
