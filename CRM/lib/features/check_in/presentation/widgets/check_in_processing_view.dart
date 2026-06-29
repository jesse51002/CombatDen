import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Fixed-height spinner body shared by the check-in dialogs (the member-page
/// single check-in and the schedule batch "Update attendees") while the
/// check-in POST + any board/detail reload run.
class CheckInProcessingView extends StatelessWidget {
  const CheckInProcessingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: DesignConstants.dialogProcessingHeight,
      child: Center(child: AppSpinner()),
    );
  }
}
