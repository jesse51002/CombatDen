import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_person_view.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_person_block.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// E4's left half: who is joining, one block per person.
///
/// The panel lists EVERYBODY the host hands it, always. A non-training payer
/// appears with no membership row (they are paying for everyone here), and
/// after a partial failure an already-charged person stays listed and is
/// MARKED ([FlowPersonView.started]) rather than dropped — removing a row is
/// indistinguishable from forgetting them, and "the next card is not charged
/// for this one" is a fact the panel must state, not imply by absence.
///
/// The mark says STARTED because the receipt one screen back has just defined
/// that word for this member.
class FlowReviewGroupPanel extends StatelessWidget {
  /// Everyone on the roster, in roster order — the payer first.
  final List<FlowPersonView> people;

  const FlowReviewGroupPanel({super.key, required this.people});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
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
          Text(copy.reviewGroupEyebrow, style: scale.eyebrow),
          for (var i = 0; i < people.length; i++) ...[
            if (i > 0) const Hairline(),
            FlowPersonBlock(person: people[i]),
          ],
        ],
      ),
    );
  }
}
