import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_rail.dart';
import 'package:crm/features/membership_flow/config/membership_flow_scale.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_rail.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// The shared workflow chrome for the add-member flow's own phases (create,
/// duplicate, created, load-detail): the expanded [AppDialog], the step rail,
/// the plain-language step-name line, the centered scrolling [body], and the
/// [footer]. The wizard phase brings its own dialog and does not use this.
///
/// The rail is the START-MEMBERSHIPS one, with its leading `Member added` rung
/// lit — because that is exactly where this flow is. Two rails describing one
/// run is how the old indicator ended up asserting a step count (`substepCount:
/// 5`) the run had long stopped having; there is one rail now, and the wizard
/// picks it up mid-ladder when it mounts.
class AddMemberChrome extends StatelessWidget {
  final String stepName;
  final Widget body;
  final Widget footer;

  const AddMemberChrome({
    super.key,
    required this.stepName,
    required this.body,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Add member & membership',
      expanded: true,
      maxWidth: DesignConstants.dialogMaxWidthWide,
      contentPadding: const EdgeInsets.all(
        DesignConstants.paddingBig,
      ),
      showCloseButton: false,
      body: MembershipFlowTheme(
        scale: const MembershipFlowScale.admin(),
        copy: const StaffFlowCopy(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            Center(
              child: FlowRail(
                // The waivers rung is derived from the plans that get picked,
                // and nothing has been picked yet — so this shows the spine
                // this flow can actually promise, and the wizard adds the rung
                // if the run turns out to owe a signature.
                steps: wizardRailSteps(
                  hasWaivers: false,
                  showAddMemberGroup: true,
                ),
                current: 0,
              ),
            ),
            Text(
              stepName,
              textAlign: TextAlign.center,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: SizedBox(
                    width: DesignConstants.dialogContentMaxWidth,
                    child: body,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: footer,
    );
  }
}
