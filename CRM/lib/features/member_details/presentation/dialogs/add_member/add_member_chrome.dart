import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step_indicator.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_step_name_line.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// The shared workflow chrome for the add-member flow's own phases (create,
/// duplicate, created, load-detail): the expanded [AppDialog] with the
/// four-group indicator (the leading "Add member" group active), the
/// plain-language step-name line, the centered scrolling [body], and the
/// [footer]. The wizard phase brings its own dialog and does not use this.
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          const StartMembershipsStepIndicator(
            step: null,
            showAddMemberGroup: true,
          ),
          StartStepNameLine(text: stepName),
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
      actions: footer,
    );
  }
}
