import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_membership_row.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';

/// Step 2 of the cancel wizard — the recurring memberships
/// the selected person can cancel, as a single-select list.
class CancelMembershipChecklist extends StatelessWidget {
  final List<CancelTarget> targets;
  final String? selectedItemId;
  final ValueChanged<String> onSelect;

  const CancelMembershipChecklist({
    super.key,
    required this.targets,
    required this.selectedItemId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty) {
      return Text(
        'No recurring memberships to cancel for this person.',
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Select a membership to cancel',
          style: DesignConstants.h3,
        ),
        Text(
          'Cancelling ends access after the current cycle. '
          'Recurring billing stops on the next billing date.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: targets
              .map(
                (t) => CancelMembershipRow(
                  target: t,
                  selected:
                      selectedItemId == t.membership.itemId,
                  onTap: () => onSelect(t.membership.itemId),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
