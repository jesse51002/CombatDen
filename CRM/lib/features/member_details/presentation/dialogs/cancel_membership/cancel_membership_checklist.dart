import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_membership_row.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';

/// The focused member's own recurring memberships as a MULTI-select
/// checklist, led by a "Cancel all memberships" select-all toggle. Selecting
/// any reveals the bulk action in the dialog footer. Already-cancelling rows
/// are shown disabled. The dialog owns the selected-id set and the
/// pay-for-others section beneath this.
class CancelMembershipChecklist extends StatelessWidget {
  final List<CancelTarget> targets;
  final Set<String> selectedItemIds;
  final void Function(String itemId, bool selected) onToggle;

  /// Selects / clears every selectable (not already-cancelling) own row.
  final ValueChanged<bool> onToggleAll;

  const CancelMembershipChecklist({
    super.key,
    required this.targets,
    required this.selectedItemIds,
    required this.onToggle,
    required this.onToggleAll,
  });

  Iterable<CancelTarget> get _selectable =>
      targets.where((t) => !t.alreadyCancelling);

  bool get _allSelected =>
      _selectable.isNotEmpty &&
      _selectable.every((t) => selectedItemIds.contains(t.itemId));

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
          'Select memberships to cancel',
          style: DesignConstants.h3,
        ),
        Text(
          'Cancelling ends access after the current cycle. '
          'Recurring billing stops on the next billing date.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        if (_selectable.length > 1)
          _CancelAllToggle(
            allSelected: _allSelected,
            onToggle: onToggleAll,
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: targets
              .map(
                (t) => CancelMembershipRow(
                  target: t,
                  selected: selectedItemIds.contains(t.itemId),
                  onChanged: (sel) => onToggle(t.itemId, sel),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

/// The "Cancel all memberships" select-all affordance above the own rows.
class _CancelAllToggle extends StatelessWidget {
  final bool allSelected;
  final ValueChanged<bool> onToggle;

  const _CancelAllToggle({
    required this.allSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onToggle(!allSelected),
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingSmall,
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              allSelected
                  ? Symbols.check_box_sharp
                  : Symbols.check_box_outline_blank_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeLarge,
              color: allSelected
                  ? DesignConstants.badRed
                  : DesignConstants.text2nd,
            ),
            Text(
              'Cancel all memberships',
              style: DesignConstants.h3,
            ),
          ],
        ),
      ),
    );
  }
}
