import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// The three-action footer for the duplicate-review step: "Back to edit"
/// (left) · "Create anyway" · "Use existing member" (primary). Shared by the
/// add-member flow and the in-run new-member dialog.
///
/// While [busy] (a create-anyway POST in flight) all three are disabled and
/// the primary shows a spinner.
class DuplicateFooter extends StatelessWidget {
  final VoidCallback onBackToEdit;
  final VoidCallback onCreateAnyway;
  final VoidCallback onUseExisting;
  final bool busy;

  const DuplicateFooter({
    super.key,
    required this.onBackToEdit,
    required this.onCreateAnyway,
    required this.onUseExisting,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        AppOutlineButton(
          text: 'Back to edit',
          onPressed: busy ? null : onBackToEdit,
          borderRadius: DesignConstants.radiusSmall,
        ),
        const Spacer(),
        AppOutlineButton(
          text: 'Create anyway',
          onPressed: busy ? null : onCreateAnyway,
          borderRadius: DesignConstants.radiusSmall,
        ),
        AppPrimaryButton(
          text: 'Use existing member',
          onPressed: busy ? null : onUseExisting,
          isLoading: busy,
          borderRadius: DesignConstants.radiusSmall,
        ),
      ],
    );
  }
}
