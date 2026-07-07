import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_bloc.dart';
import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_event.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_ready_row.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/promotable_member_row.dart';
import 'package:crm/shared/widgets/promotion_dialog.dart';

/// One member on the ready-to-promote board: the shared
/// [PromotableMemberRow] wired to the board's [ReadyToPromoteBloc]. The
/// row derives its own current → next label from the ladder, and Promote
/// opens the shared [PromotionDialog], dispatching the picked choice.
class ReadyToPromoteRow extends StatelessWidget {
  final RankReadyRow row;
  final List<MainRank> ladder;
  final RankSubType subRankType;

  const ReadyToPromoteRow({
    super.key,
    required this.row,
    required this.ladder,
    required this.subRankType,
  });

  Future<void> _openDialog(BuildContext context) async {
    final bloc = context.read<ReadyToPromoteBloc>();
    final choice = await PromotionDialog.show(
      context: context,
      ladder: ladder,
      subRankType: subRankType,
      currentMainRankId: row.mainRankId,
      currentSubIndex: row.currentSubIndex,
    );
    if (choice == null) return;
    bloc.add(ReadyPromoteRequested(
      memberId: row.memberId,
      choice: choice,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PromotableMemberRow(
      imageUrl: row.imageUrl,
      avatarUrl: row.avatarUrl,
      name: row.name,
      ladder: ladder,
      subRankType: subRankType,
      mainRankId: row.mainRankId,
      currentSubIndex: row.currentSubIndex,
      classesSince: row.classesSince,
      stepDenominator: row.stepDenominator,
      onPromote: () => _openDialog(context),
      onViewMember: () => Navigator.pushNamed(
        context,
        AppRoutes.memberDetailPath(row.memberId),
      ),
    );
  }
}
