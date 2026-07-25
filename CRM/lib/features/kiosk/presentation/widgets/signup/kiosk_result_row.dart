import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';

/// One line of what HAPPENED: a square outcome mark, then who and which plan,
/// with the consequence underneath.
///
/// It is deliberately not `KioskBuyRow`, whose own doc scopes it to "this is
/// what you are getting" — its thumb slot is the plan photo and its right slot
/// is an amount. A result row makes a different statement and carries no
/// amount, so bending the buy row to hold a status would blur the one thing
/// that doc is explicit about. Every PART here is shipped, though: the created
/// mark is `KioskBuyRow._Thumb`'s waiver square, the failed mark is
/// `KioskDeclinedScreen`'s glyph and palette squared to match it, and the two
/// text roles are the plan-name and rule roles the review already uses.
///
/// **Two rules this row holds, both against the CRM's own `StartResultRow`:**
///
/// * **No red.** Every kiosk failure surface is warm `yellowDark` / `okYellow`,
///   because nothing is broken and nobody did anything wrong. A red row on a
///   lobby iPad reads as a verdict on the person standing at it.
/// * **No raw backend error.** `StartResultRow` renders `item.error` verbatim,
///   which is right at a staff desk and wrong in a lobby: that string is Stripe
///   or internal prose. This row states the CONSEQUENCE in the kiosk's own
///   words instead.
///
/// There is also **no right-hand status word**: the mark and the sub-line
/// already carry the outcome, and one screen saying the same two words twice
/// teaches neither of them.
class KioskResultRow extends StatelessWidget {
  /// The person this membership is for, then the plan — `Marcus Bell ·
  /// Unlimited Monthly`. With no roster person to name it degrades to the plan
  /// alone: a WRONG name on a member-facing screen is worse than none.
  final String label;

  final MemberMembershipsStartStatus status;

  const KioskResultRow({
    super.key,
    required this.label,
    required this.status,
  });

  /// The consequence, in the kiosk's own words.
  ///
  /// `unknown` is the enum's forward-compatible fallback and is neither created
  /// nor failed, so it claims nothing about money in either direction — saying
  /// "nothing was charged" about a row the backend would not confirm is exactly
  /// the guess this line refuses to make.
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

/// The row's outcome square — the same geometry as the buy row's thumb, so a
/// receipt reads at the same rhythm as the review it follows.
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
