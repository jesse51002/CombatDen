import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_bloc.dart';
import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_event.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/promotion_choice.dart';
import 'package:crm/features/memberships/data/models/rank_ready_row.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/promotable_member_row.dart';
import 'package:crm/shared/widgets/promotion_dialog.dart';

/// One member on the ready-to-promote board: the shared
/// [PromotableMemberRow] wired to the board's [ReadyToPromoteBloc]. The
/// board spans ranks, so its label is the member's full "main · sub".
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

  String get _rankLabel {
    final sub = row.subLabel;
    return sub == null || sub.isEmpty ? row.mainName : '${row.mainName} · $sub';
  }

  void _quickPromote(BuildContext context) {
    context.read<ReadyToPromoteBloc>().add(
          ReadyQuickPromoteRequested(
            memberId: row.memberId,
            choice: const PromoteNextSub(),
          ),
        );
  }

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
    bloc.add(ReadyQuickPromoteRequested(
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
      rankLabel: _rankLabel,
      classesSince: row.classesSince,
      stepDenominator: row.stepDenominator,
      onQuickPromote: () => _quickPromote(context),
      onOpenDialog: () => _openDialog(context),
    );
  }
}
