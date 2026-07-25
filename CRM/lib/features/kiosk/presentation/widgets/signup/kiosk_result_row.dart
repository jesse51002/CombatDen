import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';

/// One line of what HAPPENED: a square outcome mark, then who and which plan,
/// with the consequence underneath.
///
/// Two rules hold here against the CRM's own `StartResultRow`. No RED — every
/// kiosk failure surface is warm `yellowDark` / `okYellow`, because a red row
/// on a lobby iPad reads as a verdict on the person standing at it. And no raw
/// backend error: `StartResultRow` renders `item.error` verbatim, which is
/// right at a staff desk and wrong in a lobby, so this row states the
/// CONSEQUENCE in the kiosk's own words instead.
class KioskResultRow extends StatelessWidget {
  /// The person this membership is for, then the plan — `Marcus Bell ·
  /// Unlimited Monthly`. With no roster person it degrades to the plan alone: a
  /// WRONG name on a member-facing screen is worse than none.
  final String label;

  final MemberMembershipsStartStatus status;

  const KioskResultRow({
    super.key,
    required this.label,
    required this.status,
  });

  /// The consequence, in the kiosk's own words.
  ///
  /// `unknown` (the enum's forward-compatible fallback) claims nothing about
  /// money in either direction: "nothing was charged" about a row the backend
  /// would not confirm is a guess this line refuses to make.
  String get _rule {
    return switch (status) {
      MemberMembershipsStartStatus.created => 'Started today',
      MemberMembershipsStartStatus.failed =>
        'Not started — nothing was charged for this one.',
      MemberMembershipsStartStatus.unknown =>
        'We couldn\'t confirm this one — the desk can check it for you.',
    };
  }

  @override
  Widget build(BuildContext context) {
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
                style: DesignConstants.kioskStatement,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _rule,
                style: DesignConstants.kioskCaption.copyWith(
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
