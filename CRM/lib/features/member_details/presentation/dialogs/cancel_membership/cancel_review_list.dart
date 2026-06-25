import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';

/// The review-phase summary: every membership that will be cancelled, each
/// labelled with WHOSE membership it is (the focused member, or the other
/// person they pay for) AND who pays for it. Read-only — confirmation comes
/// from the dialog footer.
class CancelReviewList extends StatelessWidget {
  final List<CancelTarget> targets;

  const CancelReviewList({
    super.key,
    required this.targets,
  });

  @override
  Widget build(BuildContext context) {
    final heading = targets.length == 1
        ? 'Cancelling 1 membership'
        : 'Cancelling ${targets.length} memberships';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(heading, style: DesignConstants.h3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: targets.map(_row).toList(),
        ),
      ],
    );
  }

  Widget _row(CancelTarget t) {
    return Row(
      spacing: DesignConstants.spacingSmall,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Symbols.cancel_sharp,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeSmall,
          color: DesignConstants.badRed,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(
                '${t.planName} · for ${t.subjectName}',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
              if (t.payerName != null)
                Text(
                  'paid by ${t.payerName}',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
