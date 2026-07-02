import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// A centered, padded [AppSpinner] for a screen's in-flight processing step —
/// shown while a mutation + reload run, replacing the editable content until
/// the bloc settles. Shared by the schedule series editor and the
/// occurrence-edit screen's `_Step.processing` step.
class CenteredProcessingView extends StatelessWidget {
  const CenteredProcessingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.paddingBig),
        child: AppSpinner(),
      ),
    );
  }
}
