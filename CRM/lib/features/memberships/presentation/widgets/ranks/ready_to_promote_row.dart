import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_bloc.dart';
import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_event.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/promotion_choice.dart';
import 'package:crm/features/memberships/data/models/rank_ready_row.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';
import 'package:crm/shared/widgets/promotion_dialog.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// One member on the ready-to-promote board: their current belt, name,
/// rank + sub-label, attendance-since-promotion progress, and a
/// one-tap **Promote** (advance one leaf) plus an overflow that opens
/// the full [PromotionDialog] for any other move.
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
    final denom = row.stepDenominator;
    final eligible = denom != null && denom > 0 && row.classesSince >= denom;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingMedium,
      ),
      child: Row(
        spacing: DesignConstants.spacingLarge,
        children: [
          RankBeltImage(imageUrl: row.imageUrl, size: 48),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingSmall,
              children: [
                Row(
                  spacing: DesignConstants.spacingMedium,
                  children: [
                    InstructorAvatar(
                      photoUrl: row.avatarUrl,
                      name: row.name,
                      diameter: 24,
                    ),
                    Expanded(
                      child: Text(
                        row.name,
                        style: DesignConstants.pSemibold,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _rankLabel,
                      style: DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text2nd,
                      ),
                    ),
                  ],
                ),
                _Progress(
                  done: row.classesSince,
                  target: denom,
                  eligible: eligible,
                ),
              ],
            ),
          ),
          AppOutlineButton(
            text: 'Promote',
            borderRadius: DesignConstants.radiusSmall,
            borderColor: eligible
                ? DesignConstants.goodGreen
                : DesignConstants.text,
            textStyle: DesignConstants.h3.copyWith(
              color:
                  eligible ? DesignConstants.goodGreen : DesignConstants.text,
            ),
            onPressed: () => _quickPromote(context),
          ),
          IconButton(
            tooltip: 'More options',
            onPressed: () => _openDialog(context),
            icon: Icon(
              Symbols.more_vert_sharp,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.text2nd,
              weight: DesignConstants.iconWeight,
            ),
          ),
        ],
      ),
    );
  }
}

/// Attendance progress toward the next leaf: "X / Y classes" over a thin
/// bar, green once the member has met the threshold.
class _Progress extends StatelessWidget {
  final int done;
  final int? target;
  final bool eligible;

  const _Progress({
    required this.done,
    required this.target,
    required this.eligible,
  });

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    final hasTarget = target != null && target > 0;
    final ratio = hasTarget ? (done / target).clamp(0.0, 1.0) : 1.0;
    final color =
        eligible ? DesignConstants.goodGreen : DesignConstants.primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingSmall,
      children: [
        Row(
          children: [
            Text(
              hasTarget ? '$done / $target classes' : '$done classes',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            const Spacer(),
            if (eligible)
              Text(
                'Eligible',
                style: DesignConstants.pSmallSemibold.copyWith(
                  color: DesignConstants.goodGreen,
                ),
              ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: DesignConstants.progressBarThickness,
            color: color,
            backgroundColor: DesignConstants.text3rd.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}
