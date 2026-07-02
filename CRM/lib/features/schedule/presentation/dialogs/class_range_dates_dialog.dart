import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/form/app_date_field.dart';

/// Plain date-range picker used to edit an existing range exception's
/// `[startDate, endDate]` — no network call, no bloc dispatch. Returns the
/// picked `(start, end)` via `Navigator.pop` when the caller taps Save, or
/// `null` on Cancel/dismiss. The caller owns the actual mutation (dispatch +
/// any destructive confirm), so both the occurrence screen and the class
/// form's "Cancelled ranges" list can reuse this one picker.
class ClassRangeDatesDialog extends StatefulWidget {
  final String className;
  final DateTime initialStart;
  final DateTime initialEnd;

  const ClassRangeDatesDialog({
    super.key,
    required this.className,
    required this.initialStart,
    required this.initialEnd,
  });

  /// Shows the picker pre-filled with [initialStart]/[initialEnd]; returns
  /// the picked dates, or null if the user backed out.
  static Future<(DateTime, DateTime)?> show({
    required BuildContext context,
    required String className,
    required DateTime initialStart,
    required DateTime initialEnd,
  }) {
    return showDialog<(DateTime, DateTime)>(
      context: context,
      builder: (_) => ClassRangeDatesDialog(
        className: className,
        initialStart: initialStart,
        initialEnd: initialEnd,
      ),
    );
  }

  @override
  State<ClassRangeDatesDialog> createState() => _ClassRangeDatesDialogState();
}

class _ClassRangeDatesDialogState extends State<ClassRangeDatesDialog> {
  late DateTime _start = widget.initialStart;
  late DateTime _end = widget.initialEnd;
  String? _inlineError;

  void _save() {
    if (_end.isBefore(_start)) {
      setState(() => _inlineError = 'The end date must be on or after start.');
      return;
    }
    Navigator.of(context).pop((_start, _end));
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Edit cancelled range',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Move the cancelled dates for ${widget.className}.',
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
          AppDateField(
            label: 'Start date',
            value: _start,
            onChanged: (d) => setState(() => _start = d),
          ),
          AppDateField(
            label: 'End date',
            value: _end,
            onChanged: (d) => setState(() => _end = d),
          ),
          if (_inlineError != null) ErrorMessage(message: _inlineError!),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Save',
        primaryOnPressed: _save,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
