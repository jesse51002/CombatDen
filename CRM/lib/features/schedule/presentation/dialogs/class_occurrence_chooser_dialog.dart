import 'package:flutter/material.dart';

import 'package:crm/features/schedule/presentation/widgets/occurrence/class_occurrence_chooser_options.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// Opened on a board card tap: a small chooser with two destinations, each a
/// distinct view over the tapped occurrence —
/// - **This occurrence** — the occurrence-edit screen (instructor / time /
///   capacity overrides for just this day, attendance, cancel-this-day).
/// - **All future occurrences** — the class definition editor (recurrence,
///   per-weekday instructors, capacity, points, image, date range).
///
/// Tapping an option closes the dialog, then runs the matching callback — the
/// caller (the board screen) owns the actual navigation so it can push with
/// its own `BuildContext` + the board's shared [ScheduleBloc].
class ClassOccurrenceChooserDialog extends StatelessWidget {
  final String className;
  final DateTime occurrenceDate;
  final VoidCallback onThisOccurrence;
  final VoidCallback onAllFuture;

  const ClassOccurrenceChooserDialog({
    super.key,
    required this.className,
    required this.occurrenceDate,
    required this.onThisOccurrence,
    required this.onAllFuture,
  });

  static Future<void> show({
    required BuildContext context,
    required String className,
    required DateTime occurrenceDate,
    required VoidCallback onThisOccurrence,
    required VoidCallback onAllFuture,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ClassOccurrenceChooserDialog(
        className: className,
        occurrenceDate: occurrenceDate,
        onThisOccurrence: onThisOccurrence,
        onAllFuture: onAllFuture,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: className,
      body: ClassOccurrenceChooserOptions(
        occurrenceDate: occurrenceDate,
        onThisOccurrence: () {
          Navigator.of(context).pop();
          onThisOccurrence();
        },
        onAllFuture: () {
          Navigator.of(context).pop();
          onAllFuture();
        },
      ),
    );
  }
}
