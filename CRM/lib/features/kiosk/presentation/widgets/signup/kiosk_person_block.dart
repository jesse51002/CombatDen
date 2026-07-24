import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_buy_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_labels.dart';

/// One person's block on the group review: their name, what marks them out,
/// and the one membership they are getting.
///
/// It is `member_review_group.dart`'s shape — a name line over the rows that
/// belong to it — carrying kiosk content. Blocked BY PERSON rather than listed
/// as memberships so "who costs what" is answerable at a glance: a parent must
/// be able to see that two children are $89 each without doing the subtraction
/// themselves.
class KioskPersonBlock extends StatelessWidget {
  final KioskSignupPerson person;

  /// The plan they picked, resolved by the caller from the warmed catalogue.
  final MembershipPlanLike? plan;

  const KioskPersonBlock({super.key, required this.person, this.plan});

  @override
  Widget build(BuildContext context) {
    final chosen = plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        _NameLine(person: person),
        if (chosen != null)
          KioskBuyRow(
            name: chosen.name,
            rule: chosen.rule,
            imageUrl: chosen.imageUrl,
            amount: chosen.priceMinorUnits == null
                ? null
                : formatMinorUnits(chosen.priceMinorUnits!, currency: 'USD'),
          ),
      ],
    );
  }
}

/// The plan facts this block renders, resolved once by the caller so the block
/// never reaches into the catalogue itself.
class MembershipPlanLike {
  final String name;
  final String? rule;
  final String? imageUrl;

  /// The plan's own list price. The authoritative charge is the preview's, on
  /// the money panel beside this — this is "what you picked", not "what you
  /// pay", exactly as the solo review already renders it.
  final int? priceMinorUnits;

  const MembershipPlanLike({
    required this.name,
    this.rule,
    this.imageUrl,
    this.priceMinorUnits,
  });

  /// The facts of the plan [person] picked, or null when they picked none.
  static MembershipPlanLike? of(
    KioskSignupState state,
    KioskSignupPerson person,
  ) {
    final plan = state.planById(person.selectedPlanId);
    if (plan == null) return null;
    return MembershipPlanLike(
      name: plan.planName,
      rule: kioskPlanRuleLabel(plan),
      imageUrl: plan.imageUrl,
      priceMinorUnits: plan.activePrice?.price,
    );
  }
}

class _NameLine extends StatelessWidget {
  final KioskSignupPerson person;

  const _NameLine({required this.person});

  @override
  Widget build(BuildContext context) {
    final name = '${person.firstName} ${person.lastName}'.trim();
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            name,
            style: DesignConstants.kioskName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (person.isPayer)
          Text(
            'PAYING',
            style: DesignConstants.kioskEyebrow.copyWith(
              color: DesignConstants.primaryColor,
            ),
          )
        else if (person.wasExisting)
          Text(
            'MEMBER',
            style: DesignConstants.kioskEyebrow.copyWith(
              color: DesignConstants.text2nd,
            ),
          )
        else
          Text(
            'NEW',
            style: DesignConstants.kioskEyebrow.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}
