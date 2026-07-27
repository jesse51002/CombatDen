import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// A nested staff dialog's footer, in the run's own three-slot shape: the
/// destructive verb exiled to the far LEFT gutter, and the decision pair
/// (secondary + primary) centred on the whole band.
///
/// A `Stack` rather than a three-way `Row`, for the same reason `FlowFoot` is:
/// the pair's optical centre is then identical whether or not the gutter
/// carries anything, so the primary never shifts under the cursor between one
/// phase of a task and the next.
///
/// The gutter is the ONLY place a destructive action may sit, and it is a full
/// stage away from the primary — the two are different verbs and must never be
/// mis-tapped for one another.
class TaskFoot extends StatelessWidget {
  final String primaryLabel;

  /// Null disables the primary — an incomplete form, or a commit in flight.
  final VoidCallback? onPrimary;

  /// The primary shows a spinner and refuses a second press.
  final bool busy;

  /// The centred pair's quieter half (Cancel / Back).
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// The left gutter. Only for a verb that takes something away.
  final String? destructiveLabel;
  final VoidCallback? onDestructive;

  const TaskFoot({
    super.key,
    required this.primaryLabel,
    this.onPrimary,
    this.busy = false,
    this.secondaryLabel,
    this.onSecondary,
    this.destructiveLabel,
    this.onDestructive,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final destructive = destructiveLabel;
    final secondary = secondaryLabel;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (destructive != null)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppOutlineButton(
                text: destructive,
                onPressed: onDestructive,
                borderColor: DesignConstants.badRed,
                textStyle: scale.buttonOutlineLabel.copyWith(
                  color: DesignConstants.badRed,
                ),
                padding: scale.buttonOutlinePadding,
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            if (secondary != null)
              AppOutlineButton(
                text: secondary,
                onPressed: onSecondary,
                textStyle: scale.buttonOutlineLabel,
                padding: scale.buttonOutlinePadding,
              ),
            AppPrimaryButton(
              text: primaryLabel,
              onPressed: onPrimary,
              isLoading: busy,
              textStyle: scale.buttonPrimaryLabel,
              padding: scale.buttonPrimaryPadding,
            ),
          ],
        ),
      ],
    );
  }
}
