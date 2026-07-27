import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_person_view.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_buy_row.dart';

/// One person's block on the group review: their name, what marks them out,
/// and the one membership they are getting.
///
/// `member_review_group.dart`'s shape. Blocked BY PERSON rather than listed as
/// memberships so "who costs what" is answerable at a glance without doing the
/// subtraction.
class FlowPersonBlock extends StatelessWidget {
  /// Who they are, what marks them out, and the plan they picked — all
  /// resolved by the host, so the block never reaches into a catalogue.
  final FlowPersonView person;

  const FlowPersonBlock({super.key, required this.person});

  @override
  Widget build(BuildContext context) {
    final chosen = person.plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        _NameLine(person: person),
        if (chosen != null)
          FlowBuyRow(
            name: chosen.name,
            rule: chosen.rule,
            imageUrl: chosen.imageUrl,
            amount: chosen.amountLabel,
          ),
      ],
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
  final FlowPersonView person;

  const _NameLine({required this.person});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            person.fullName,
            style: scale.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          switch (person.role) {
            FlowPersonRole.paying => copy.payingEyebrow,
            FlowPersonRole.member => copy.memberEyebrow,
            FlowPersonRole.newcomer => copy.newcomerEyebrow,
          },
          style: scale.eyebrow.copyWith(
            color: person.role == FlowPersonRole.paying
                ? DesignConstants.primaryColor
                : DesignConstants.text2nd,
          ),
        ),
        if (person.started)
          Text(
            copy.startedEyebrow,
            style: scale.eyebrow.copyWith(
              color: DesignConstants.goodGreen,
            ),
          ),
      ],
    );
  }
}
