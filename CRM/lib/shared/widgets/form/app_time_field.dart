import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/shared/widgets/form/tappable_field.dart';

/// Labeled time field. Tapping opens a time picker; the chosen time is
/// shown in the locale's format (e.g. "6:00 PM").
///
/// [label] is optional — omit it when the surrounding layout already labels
/// the field (e.g. a column-header row above a list of repeating rows); the
/// underlying [TappableField] simply renders the box on its own.
class AppTimeField extends StatelessWidget {
  final String? label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay>? onChanged;
  final String hintText;

  const AppTimeField({
    super.key,
    this.label,
    this.value,
    this.onChanged,
    this.hintText = 'Select time',
  });

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: value ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked != null) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TappableField(
      label: label,
      valueText: value?.format(context),
      hintText: hintText,
      icon: Symbols.schedule_sharp,
      onTap: () => _pick(context),
    );
  }
}
