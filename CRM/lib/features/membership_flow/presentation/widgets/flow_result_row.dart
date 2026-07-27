import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// One line of what HAPPENED: a square outcome mark, then who and which plan,
/// with the consequence underneath.
///
/// Two rules hold here against the CRM's own `StartResultRow`. No RED — every
/// kiosk failure surface is warm `yellowDark` / `okYellow`, because a red row
/// on a lobby iPad reads as a verdict on the person standing at it. And no raw
/// backend error: `StartResultRow` renders `item.error` verbatim, which is
/// right at a staff desk and wrong in a lobby, so this row states the
/// CONSEQUENCE in the kiosk's own words instead.
class FlowResultRow extends StatelessWidget {
  /// The person this membership is for, then the plan — `Marcus Bell ·
  /// Unlimited Monthly`. With no roster person it degrades to the plan alone: a
  /// WRONG name on a member-facing screen is worse than none.
  final String label;

  final MemberMembershipsStartStatus status;

  /// The backend's OWN words about this one membership, under the consequence.
  ///
  /// Null on the kiosk, and that absence is the rule this widget's second
  /// paragraph states: a raw backend message is right at a staff desk — where
  /// somebody has to act on "insufficient funds" — and wrong in a lobby, where
  /// it reads as a verdict on the person standing at the screen. The
  /// consequence above it is stated either way, so the row never depends on
  /// this line to make sense.
  final String? detail;

  const FlowResultRow({
    super.key,
    required this.label,
    required this.status,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        _Mark(status: status),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                label,
                style: scale.statement,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              // The CONSEQUENCE, never the backend's error: a raw message is
              // right at a staff desk and wrong in a lobby, so the surface's
              // own copy states what it means for this one membership.
              Text(
                copy.resultConsequence(status),
                style: scale.caption.copyWith(
                  color: DesignConstants.text2nd,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (detail case final reason? when reason.trim().isNotEmpty)
                Text(
                  reason,
                  style: scale.micro.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The row's outcome square — the buy row's thumb geometry, so a receipt reads
/// at the same rhythm as the review it follows.
class _Mark extends StatelessWidget {
  final MemberMembershipsStartStatus status;

  const _Mark({required this.status});

  @override
  Widget build(BuildContext context) {
    final created = status == MemberMembershipsStartStatus.created;
    final side = DesignConstants.iconSizeBig + DesignConstants.spacingLarge;
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: created
            ? DesignConstants.goodGreen.withValues(alpha: 0.14)
            : DesignConstants.yellowDark,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Icon(
        switch (status) {
          MemberMembershipsStartStatus.created => Symbols.check_sharp,
          MemberMembershipsStartStatus.failed => Symbols.credit_card_off_sharp,
          // Pending, not refused: the backend would not say either way.
          MemberMembershipsStartStatus.unknown => Symbols.pending_sharp,
        },
        size: DesignConstants.iconSizeLarge,
        weight: DesignConstants.iconWeight,
        color:
            created ? DesignConstants.goodGreen : DesignConstants.okYellow,
      ),
    );
  }
}
