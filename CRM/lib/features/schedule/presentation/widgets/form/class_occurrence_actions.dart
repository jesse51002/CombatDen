import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

final DateFormat _dateLabel = DateFormat('EEEE, MMM d, yyyy');

/// Single-occurrence actions inside the class edit form, shown when the form
/// was opened from a tapped board card (a specific date). Mirrors the retired
/// manage-popup's choices, now in-screen:
/// - **Update attendees** — opens the batch staff check-in for this date
///   (offered for any non-cancelled occurrence, past or upcoming).
/// - **Cancel this class** — cancels just this date ([cancellable] only: an
///   upcoming, not-already-cancelled occurrence).
/// A cancelled occurrence shows a note instead of the actions.
class ClassOccurrenceActions extends StatelessWidget {
  final DateTime occurrenceDate;
  final bool cancellable;
  final bool isCancelled;
  final VoidCallback onUpdateAttendees;
  final VoidCallback onCancelInstance;

  const ClassOccurrenceActions({
    super.key,
    required this.occurrenceDate,
    required this.cancellable,
    required this.isCancelled,
    required this.onUpdateAttendees,
    required this.onCancelInstance,
  });

  String get _note {
    final date = _dateLabel.format(occurrenceDate);
    if (isCancelled) return 'This class is cancelled on $date.';
    return 'Manage who attended on $date, or cancel just this day.';
  }

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'This session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            _note,
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
          if (!isCancelled)
            Row(
              spacing: DesignConstants.spacingLarge,
              children: [
                AppOutlineButton(
                  text: 'Update attendees',
                  onPressed: onUpdateAttendees,
                ),
                if (cancellable)
                  AppOutlineButton(
                    text: 'Cancel this class',
                    onPressed: onCancelInstance,
                    borderColor: DesignConstants.badRed,
                    textColor: DesignConstants.badRed,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
