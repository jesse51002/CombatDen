import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/shared/widgets/form/tappable_field.dart';

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

  const AppDateField({
    super.key,
    required this.label,
    this.value,
    this.onChanged,
    this.hintText = 'Select date',
  });

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime(2026, 2, 1),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
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
