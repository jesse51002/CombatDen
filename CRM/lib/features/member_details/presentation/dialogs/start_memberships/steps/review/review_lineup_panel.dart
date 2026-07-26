import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/review/review_person_block.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The review's left half: who is getting what, one block per person.
///
/// It survives a failed price: the money half beside it can go to a retry
/// block and this panel stays exactly as it was, because the lineup is the
/// thing staff spent the run building and nothing about a billing timeout
/// should cost them it.
class WizardReviewLineupPanel extends StatelessWidget {
  final MembershipWizardState state;
  final ValueChanged<String> onEdit;
  final void Function(String memberId, String planId) onRemove;

  const WizardReviewLineupPanel({
    super.key,
    required this.state,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final copy = MembershipFlowTheme.copyOf(context);
    final scale = MembershipFlowTheme.of(context);
    final people = state.people;
    return WizardPanel(
      children: [
        Text(copy.reviewGroupEyebrow, style: scale.eyebrow),
        for (var i = 0; i < people.length; i++) ...[
          if (i > 0) const Hairline(),
          WizardReviewPersonBlock(
            state: state,
            person: people[i],
            onEdit: onEdit,
            onRemove: onRemove,
          ),
        ],
        const Hairline(),
        // Said BEFORE a trash can is used: the row below it is the one control
        // on this screen that can take somebody out of the run.
        Text(
          WizardReviewCopy.removalNote,
          style: scale.caption.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
