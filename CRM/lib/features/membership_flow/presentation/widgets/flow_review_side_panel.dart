import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_person_view.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_signed_waiver_view.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_buy_row.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// The review's left half: who this is, what they picked, and what they have
/// already signed.
///
/// `Signed today by <name>` is the receipt for the thing that has no receipt —
/// somebody who typed their name into a legal document two screens ago sees it
/// acknowledged before handing over a card.
///
/// The address is whatever the HOST decided this surface may print
/// ([FlowPersonView.identityLine]); the kiosk masks it, because a lobby iPad
/// has a queue reading over the member's shoulder. The one address they must
/// CHECK is the receipt one, which the money panel beside this states in full.
class FlowReviewSidePanel extends StatelessWidget {
  /// The one person this review is about, carrying the plan they picked.
  final FlowPersonView person;

  /// What has been signed during this purchase, in signing order.
  final List<FlowSignedWaiverView> signed;

  const FlowReviewSidePanel({
    super.key,
    required this.person,
    this.signed = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    final plan = person.plan;
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(copy.reviewPersonEyebrow, style: scale.eyebrow),
          _WhoRow(name: person.fullName, line: person.identityLine),
          Text(copy.reviewMembershipEyebrow, style: scale.eyebrow),
          if (plan != null)
            FlowBuyRow(
              name: plan.name,
              rule: plan.rule,
              imageUrl: plan.imageUrl,
              amount: plan.amountLabel,
            ),
          for (final waiver in signed)
            FlowBuyRow(
              name: waiver.name,
              rule: copy.waiverSignedRule(waiver.signerName),
            ),
        ],
      ),
    );
  }
}

class _WhoRow extends StatelessWidget {
  final String name;

  /// Their address, already resolved by the host. Null drops the line.
  final String? line;

  const _WhoRow({required this.name, required this.line});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final second = line;
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        InstructorAvatar(name: name, diameter: DesignConstants.iconSizeBig),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                name,
                style: scale.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (second != null)
                Text(
                  second,
                  style: scale.caption.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
