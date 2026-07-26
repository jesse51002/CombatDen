import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/domain/plan_labels.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_buy_row.dart';

/// One person's block on the group review: their name, what marks them out,
/// and the one membership they are getting.
///
/// `member_review_group.dart`'s shape carrying kiosk content. Blocked BY PERSON
/// rather than listed as memberships so "who costs what" is answerable at a
/// glance without doing the subtraction.
class FlowPersonBlock extends StatelessWidget {
  final KioskSignupPerson person;

  /// The plan they picked, resolved by the caller from the warmed catalogue.
  final MembershipPlanLike? plan;

  /// Their membership already STARTED on an earlier attempt, so the card about
  /// to be entered is not charged for them ([KioskSignupState.alreadyStarted]).
  /// It adds a mark; it never removes the row.
  final bool started;

  const FlowPersonBlock({
    super.key,
    required this.person,
    this.plan,
    this.started = false,
  });

  @override
  Widget build(BuildContext context) {
    final chosen = plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        _NameLine(person: person, started: started),
        if (chosen != null)
          FlowBuyRow(
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

/// The plan facts this block renders, resolved by the caller so the block never
/// reaches into the catalogue itself.
class MembershipPlanLike {
  final String name;
  final String? rule;
  final String? imageUrl;

  /// The plan's own list price — "what you picked", not "what you pay". The
  /// authoritative charge is the preview's, on the money panel beside this.
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
      rule: planAllowanceLabel(plan),
      imageUrl: plan.imageUrl,
      priceMinorUnits: plan.activePrice?.price,
    );
  }
}

/// The name, then the eyebrow labels that qualify it.
///
/// The role label and the STARTED mark both render — never one instead of the
/// other. They answer different questions ("whose card is this" and "is this
/// one already paid for") and the payer can easily be the person whose
/// membership already started.
class _NameLine extends StatelessWidget {
  final KioskSignupPerson person;

  /// Their membership already started — see `FlowPersonBlock.started`.
  final bool started;

  const _NameLine({required this.person, this.started = false});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final name = '${person.firstName} ${person.lastName}'.trim();
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            name,
            style: scale.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (person.isPayer)
          Text(
            'PAYING',
            style: scale.eyebrow.copyWith(
              color: DesignConstants.primaryColor,
            ),
          )
        else if (person.wasExisting)
          Text(
            'MEMBER',
            style: scale.eyebrow.copyWith(
              color: DesignConstants.text2nd,
            ),
          )
        else
          Text(
            'NEW',
            style: scale.eyebrow.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        if (started)
          Text(
            'STARTED',
            style: scale.eyebrow.copyWith(
              color: DesignConstants.goodGreen,
            ),
          ),
      ],
    );
  }
}
