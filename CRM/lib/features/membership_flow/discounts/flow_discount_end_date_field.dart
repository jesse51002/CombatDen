import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/discounts/discount_copy.dart';
import 'package:crm/features/membership_flow/discounts/discount_labels.dart';

/// The last day a custom discount applies — the `end_date` half of the
/// backend's lifetime spec, finally reachable from a screen.
///
/// **Staff-only** — see `discount_labels.dart`.
///
/// It can never hold an INVALID answer, which is why the form has no
/// fifth validation message for it: the field is created with a real date
/// already in it, and the picker it opens starts at tomorrow, so "no date" and
/// "a date already past" are both unreachable rather than rejected. A date on
/// or before today would be a discount the backend's own read drops
/// immediately (`end_date > :today`) — a discount that silently never applies
/// is the worst outcome available here.
///
/// The note under it states the cutoff is INCLUSIVE and that the bill after it
/// is the full price again, because "until" is ambiguous about both.
class FlowDiscountEndDateField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const FlowDiscountEndDateField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// How far ahead the picker lets staff reach. A decade is past any promotion
  /// anybody is actually running and short of the dates a mis-scroll produces.
  static const int _yearsAhead = 10;

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(FlowDiscountCopy.endDateLabel, style: scale.label),
        InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          child: Container(
            // The typed fields' own box, so a picker-backed field never reads
            // as a different KIND of control.
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingSmall,
              vertical: DesignConstants.spacingMedium,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.card,
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              border: Border.all(color: DesignConstants.text),
              boxShadow: DesignConstants.controlShadow,
            ),
            child: Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                Icon(
                  Symbols.calendar_month_sharp,
                  size: DesignConstants.iconSizeLarge,
                  weight: DesignConstants.iconWeight,
                  color: DesignConstants.text2nd,
                ),
                Expanded(
                  child: Text(
                    flowDiscountDay(value),
                    style: scale.fieldText.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          FlowDiscountCopy.endDateNote(flowDiscountDay(value)),
          style: scale.caption.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context) async {
    final today = DateTime.now();
    final earliest = DateTime(today.year, today.month, today.day + 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: value.isBefore(earliest) ? earliest : value,
      firstDate: earliest,
      lastDate: DateTime(today.year + _yearsAhead, today.month, today.day),
    );
    if (picked != null) onChanged(picked);
  }
}

/// The date an end-date lifetime STARTS out on, so the field is never empty
/// and the form never has to reject a missing one.
///
/// A month out: long enough to be a plausible promotion, short enough that
/// leaving it untouched is obviously not what staff meant.
DateTime flowDefaultDiscountEndDate() {
  final today = DateTime.now();
  return DateTime(today.year, today.month + 1, today.day);
}
