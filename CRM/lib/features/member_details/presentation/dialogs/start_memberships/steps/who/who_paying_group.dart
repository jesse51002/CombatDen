import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_detail_group.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// WHO'S PAYING — a control on the roster rather than a screen of its own.
///
/// The old flow asked for the payer on a separate step, which is what left two
/// adder pairs on two screens with identical copy pointing in opposite
/// directions. Here the fact is stated where the roster it explains is, and
/// changing it is one named button.
///
/// The warning is said BEFORE the control is used: the switch rebuilds the
/// roster and cannot be undone, so a consequence stated afterwards would be an
/// apology rather than a choice.
class WhoPayingGroup extends StatelessWidget {
  final String payerName;
  final VoidCallback onChangePayer;

  const WhoPayingGroup({
    super.key,
    required this.payerName,
    required this.onChangePayer,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return FlowDetailGroup(
      eyebrow: WizardWhoCopy.payingEyebrow,
      children: [
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            InstructorAvatar(
              name: payerName,
              diameter: DesignConstants.iconSizeLarge,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingSmall,
                children: [
                  Text(
                    WizardWhoCopy.paysForEveryone(payerName),
                    style: scale.label,
                  ),
                  Text(
                    WizardWhoCopy.payerSwitchWarning,
                    style: scale.caption.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
            AppOutlineButton(
              text: WizardWhoCopy.changePayer,
              onPressed: onChangePayer,
              textStyle: scale.buttonOutlineLabel,
              borderWidth: DesignConstants.buttonBorder,
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.spacingLarge,
                vertical: DesignConstants.spacingMedium,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
