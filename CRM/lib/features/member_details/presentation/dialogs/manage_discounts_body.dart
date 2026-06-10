import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/manage_discounts_add_section.dart';
import 'package:crm/features/member_details/presentation/dialogs/manage_discounts_remove_section.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// The body of the manage-discounts dialog: a two-screen card.
/// An **Add** screen lists the gym's not-yet-applied presets;
/// a **Remove** screen lists the applied-discount rows already applied to
/// this member's line. Pure presentation — selection and the
/// single combined apply/remove commit live in the dialog.
class ManageDiscountsBody extends StatelessWidget {
  final List<DiscountResponse> presets;
  final bool loadFailed;
  final Set<String> appliedSourceIds;
  final List<DiscountInfo> appliedDiscounts;
  final Set<String> selectedToAdd;
  final Set<String> selectedToRemove;
  final int activeTab;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<String> onToggleAdd;
  final ValueChanged<String> onToggleRemove;

  const ManageDiscountsBody({
    super.key,
    required this.presets,
    required this.loadFailed,
    required this.appliedSourceIds,
    required this.appliedDiscounts,
    required this.selectedToAdd,
    required this.selectedToRemove,
    required this.activeTab,
    required this.onTabChanged,
    required this.onToggleAdd,
    required this.onToggleRemove,
  });

  List<DiscountResponse> get _addable => presets
      .where((p) => !appliedSourceIds.contains(p.discountId))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        ViewSwitcher(
          labels: const ['Add', 'Remove'],
          selectedIndex: activeTab,
          onSelected: onTabChanged,
        ),
        if (activeTab == 0)
          ManageDiscountsAddSection(
            addable: _addable,
            loadFailed: loadFailed,
            selectedToAdd: selectedToAdd,
            onToggle: onToggleAdd,
          )
        else
          ManageDiscountsRemoveSection(
            applied: appliedDiscounts,
            selectedToRemove: selectedToRemove,
            onToggle: onToggleRemove,
          ),
      ],
    );
  }
}
