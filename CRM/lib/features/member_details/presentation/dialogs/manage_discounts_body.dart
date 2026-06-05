import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/presentation/widgets/discount_lifetime_label.dart';
import 'package:crm/shared/widgets/discount_grid.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';

/// The body of the manage-discounts dialog: already-applied
/// snapshots (read-only), the gym's not-yet-applied presets
/// to add. Pure
/// presentation — selection + apply live in the dialog.
class ManageDiscountsBody extends StatelessWidget {
  final List<DiscountResponse> presets;
  final bool loadFailed;
  final Set<String> appliedSourceIds;
  final List<DiscountInfo> appliedDiscounts;
  final Set<String> selectedToAdd;
  final ValueChanged<String> onToggle;

  const ManageDiscountsBody({
    super.key,
    required this.presets,
    required this.loadFailed,
    required this.appliedSourceIds,
    required this.appliedDiscounts,
    required this.selectedToAdd,
    required this.onToggle,
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
        if (appliedDiscounts.isNotEmpty)
          _AppliedList(applied: appliedDiscounts),
        _AddableSection(
          addable: _addable,
          loadFailed: loadFailed,
          selectedToAdd: selectedToAdd,
          onToggle: onToggle,
        ),
      ],
    );
  }
}

/// Read-only list of the discounts already frozen onto this
/// line — staff remove them from the section table, not here.
class _AppliedList extends StatelessWidget {
  final List<DiscountInfo> applied;

  const _AppliedList({required this.applied});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Already applied',
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Wrap(
          spacing: DesignConstants.spacingSmall,
          runSpacing: DesignConstants.spacingSmall,
          children: applied
              .map(
                (d) => InvoiceChip(
                  label: '${d.discountName} · '
                      '${d.discountLabel}',
                  tone: d.isLinked
                      ? InvoiceChipTone.brand
                      : InvoiceChipTone.good,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

/// The selectable not-yet-applied presets to add, or the
/// load-failed / empty messages.
class _AddableSection extends StatelessWidget {
  final List<DiscountResponse> addable;
  final bool loadFailed;
  final Set<String> selectedToAdd;
  final ValueChanged<String> onToggle;

  const _AddableSection({
    required this.addable,
    required this.loadFailed,
    required this.selectedToAdd,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (loadFailed) {
      return _Message(
        text: 'Couldn’t load discounts. Please try again.',
      );
    }
    if (addable.isEmpty) {
      return _Message(
        text: 'No more discounts to add.',
        icon: Symbols.check_circle_sharp,
      );
    }
    final options = addable
        .map(
          (d) => DiscountOption(
            id: d.discountId,
            name: d.discountName,
            valueLabel: d.displayLabel,
            durationLabel: discountLifetimeLabel(d),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Add a discount',
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        DiscountGrid(
          discounts: options,
          selectedIds: selectedToAdd,
          onToggle: (d) => onToggle(d.id),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final IconData? icon;

  const _Message({required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        if (icon != null)
          Icon(
            icon,
            size: DesignConstants.iconSizeMedium,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text2nd,
          ),
        Flexible(
          child: Text(
            text,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
      ],
    );
  }
}
