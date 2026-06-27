import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_membership_row.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';

/// The secondary cancel scope, surfaced only when the focused member ALSO
/// pays for other people. A header toggle ("Also cancel the memberships you
/// pay for others") selects / clears every pay-for-others membership at once;
/// individual rows below let staff fine-tune. Each row is labelled with whose
/// membership it is (the subject member's name).
class CancelPayForOthersSection extends StatelessWidget {
  final List<CancelTarget> targets;
  final Set<String> selectedItemIds;
  final void Function(String itemId, bool selected) onToggle;
  final ValueChanged<bool> onToggleAll;

  const CancelPayForOthersSection({
    super.key,
    required this.targets,
    required this.selectedItemIds,
    required this.onToggle,
    required this.onToggleAll,
  });

  bool get _allSelected =>
      targets.isNotEmpty &&
      targets.every((t) => selectedItemIds.contains(t.itemId));

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Divider(
          color: DesignConstants.divider,
          height: DesignConstants.dividerThickness,
          thickness: DesignConstants.dividerThickness,
        ),
        _OthersToggle(
          allSelected: _allSelected,
          count: targets.length,
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

/// The header toggle for the pay-for-others scope.
class _OthersToggle extends StatelessWidget {
  final bool allSelected;
  final int count;
  final ValueChanged<bool> onToggle;

  const _OthersToggle({
    required this.allSelected,
    required this.count,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final label = count == 1
        ? 'Also cancel the 1 membership you pay for others'
        : 'Also cancel the $count memberships you pay for others';
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
            Expanded(
              child: Text(
                label,
                style: DesignConstants.h3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
