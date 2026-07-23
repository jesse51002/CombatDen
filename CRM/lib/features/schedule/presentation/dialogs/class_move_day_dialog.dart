import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/form/app_date_field.dart';

/// Single-date picker for moving ONE class occurrence to another day — the
/// front-desk "Move to another day (same time)" affordance. Date only: the
/// occurrence keeps its original start time, so this picks just the new day.
/// No network call, no bloc dispatch — like `ClassRangeDatesDialog`, it returns
/// the picked day via `Navigator.pop` (or null on Cancel/dismiss) and the
/// caller owns the actual reschedule (its warn + dispatch + terminal state).
class ClassMoveDayDialog extends StatefulWidget {
  final String className;

  /// The occurrence's current time range label (e.g. `6:00 PM - 7:00 PM`),
  /// shown so it's clear the time is preserved.
  final String timeLabel;

  /// The occurrence's current (effective) day — the picker opens here, and
  /// re-picking it is blocked as a no-op move.
  final DateTime initialDate;

  const ClassMoveDayDialog({
    super.key,
    required this.className,
    required this.timeLabel,
    required this.initialDate,
  });

  /// Shows the picker opened on [initialDate]; returns the picked new day, or
  /// null if the user backed out.
  static Future<DateTime?> show({
    required BuildContext context,
    required String className,
    required String timeLabel,
    required DateTime initialDate,
  }) {
    return showDialog<DateTime>(
      context: context,
      builder: (_) => ClassMoveDayDialog(
        className: className,
        timeLabel: timeLabel,
        initialDate: initialDate,
      ),
    );
  }

  @override
  State<ClassMoveDayDialog> createState() => _ClassMoveDayDialogState();
}

class _ClassMoveDayDialogState extends State<ClassMoveDayDialog> {
  late DateTime _date = widget.initialDate;
  String? _inlineError;

  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _save() {
    if (_isSameDate(_date, widget.initialDate)) {
      setState(() =>
          _inlineError = 'Pick a different day — this is the current date.');
      return;
    }
    Navigator.of(context).pop(_date);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Move to another day',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Pick a new day for ${widget.className}. It keeps the same start '
            'time (${widget.timeLabel}); reservations move with it.',
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
          AppDateField(
            label: 'New day (same time)',
            value: _date,
            onChanged: (d) => setState(() {
              _date = d;
              _inlineError = null;
            }),
          ),
          if (_inlineError != null) ErrorMessage(message: _inlineError!),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Move class',
        primaryOnPressed: _save,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
