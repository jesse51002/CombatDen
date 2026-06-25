import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Start / end date buttons plus a clear affordance for the members
/// filter dialog's start-date range. Dates are membership start dates,
/// so the pickers cap at today; picking a start after the end (or vice
/// versa) swaps them so the range stays valid.
class MembersListFilterDateField extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final void Function(DateTime? start, DateTime? end) onChanged;

  const MembersListFilterDateField({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.onChanged,
  });

  Future<void> _pick(
    BuildContext context, {
    required bool isStart,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? startDate : endDate) ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null) return;

    var start = isStart ? picked : startDate;
    var end = isStart ? endDate : picked;
    if (start != null && end != null && start.isAfter(end)) {
      final swap = start;
      start = end;
      end = swap;
    }
    onChanged(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy');
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: _DateButton(
            label: startDate == null
                ? 'Start date'
                : fmt.format(startDate!),
            isSet: startDate != null,
            onPressed: () => _pick(context, isStart: true),
          ),
        ),
        Expanded(
          child: _DateButton(
            label: endDate == null
                ? 'End date'
                : fmt.format(endDate!),
            isSet: endDate != null,
            onPressed: () => _pick(context, isStart: false),
          ),
        ),
        if (startDate != null || endDate != null)
          IconButton(
            onPressed: () => onChanged(null, null),
            tooltip: 'Clear dates',
            icon: Icon(
              Symbols.close_sharp,
              color: DesignConstants.text2nd,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeSmall,
            ),
          ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final bool isSet;
  final VoidCallback onPressed;

  const _DateButton({
    required this.label,
    required this.isSet,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AppOutlineButton(
      text: label,
      onPressed: onPressed,
      fullWidth: true,
      borderRadius: DesignConstants.radiusSmall,
      borderColor: DesignConstants.line,
      textColor:
          isSet ? DesignConstants.text : DesignConstants.text3rd,
      textStyle: DesignConstants.p,
    );
  }
}
