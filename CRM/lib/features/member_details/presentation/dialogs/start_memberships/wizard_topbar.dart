import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';

/// The wizard's context bar, in place of the dialog's own title row.
///
/// It carries the two facts no step can: WHOSE record this run was opened
/// from — the payer may be somebody else entirely by the second screen — and
/// how far through the run staff actually are. The step counter is over the
/// REAL spine (`5 + N`), which is what makes it safe to keep the rail down to
/// six named stages.
///
/// The close X is disabled while the start POST is in flight: the one moment
/// leaving would strand a charge whose outcome nobody has read yet.
class WizardTopBar extends StatelessWidget {
  /// The member whose page opened the run.
  final String launchMemberName;

  /// The gym, where it is known. Empty drops the clause rather than printing
  /// a trailing separator.
  final String gymName;

  /// One-based position in the run's own spine, and its length.
  final int step;
  final int stepCount;

  /// Null while the run may not be abandoned.
  final VoidCallback? onClose;

  const WizardTopBar({
    super.key,
    required this.launchMemberName,
    required this.gymName,
    required this.step,
    required this.stepCount,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final gym = gymName.trim();
    final who = gym.isEmpty
        ? WizardChromeCopy.openedFrom(launchMemberName)
        : WizardChromeCopy.openedFromAt(launchMemberName, gym);
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(WizardChromeCopy.dialogTitle, style: DesignConstants.h3),
        Expanded(
          child: Text(
            who,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          WizardChromeCopy.stepOf(step, stepCount),
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: Icon(
            Symbols.close_sharp,
            color: DesignConstants.text2nd,
            weight: DesignConstants.iconWeight,
          ),
          tooltip: WizardChromeCopy.closeSemantic,
        ),
      ],
    );
  }
}
