import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/shared/widgets/form/tappable_field.dart';

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// Labeled date field. Tapping opens a date picker; the chosen date is
/// shown as "MMM d, yyyy".
class AppDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime>? onChanged;
  final String hintText;

  /// Picker bounds. Default to the existing `2020`/`2030` span when omitted
  /// (unchanged for existing callers); pass [firstDate] to floor the picker —
  /// e.g. a forward-only reschedule field.
  final DateTime? firstDate;
  final DateTime? lastDate;

  const AppDateField({
    super.key,
    required this.label,
    this.value,
    this.onChanged,
    this.hintText = 'Select date',
    this.firstDate,
    this.lastDate,
  });

  Future<void> _pick(BuildContext context) async {
    final first = firstDate ?? DateTime(2020);
    final last = lastDate ?? DateTime(2030);
    // An empty field opens at today; a filled one at its value. Either may
    // sit outside the caller's bounds (e.g. a reschedule field defaults to
    // the occurrence's original date, before a forward-only floor) — clamp
    // so `showDatePicker`'s initialDate-in-range assertion never fires.
    var initial = value ?? DateTime.now();
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TappableField(
      label: label,
      valueText: value != null ? _formatDate(value!) : null,
      hintText: hintText,
      icon: Symbols.calendar_month_sharp,
      onTap: () => _pick(context),
    );
  }
}
