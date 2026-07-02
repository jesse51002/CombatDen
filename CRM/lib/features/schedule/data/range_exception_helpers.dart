/// Shared logic + copy for editing/removing a CANCEL range exception —
/// used by both the occurrence screen's "Cancelled by a range" section and
/// the class form's "Cancelled ranges" list, so wording and the widen check
/// can never drift between the two surfaces.
library;

/// Whether moving a range from `[oldStart, oldEnd]` to `[newStart, newEnd]`
/// WIDENS its coverage — the new bounds reach at least one day the old
/// bounds didn't. Narrowing (or an identical range) returns false, so the
/// destructive "newly covered dates lose their reservations/check-ins"
/// warning is shown only when it's actually true.
bool rangeWidensCoverage({
  required DateTime oldStart,
  required DateTime oldEnd,
  required DateTime newStart,
  required DateTime newEnd,
}) =>
    newStart.isBefore(oldStart) || newEnd.isAfter(oldEnd);

/// Confirm copy shown before saving an EDIT that widens a cancelled range's
/// coverage (only shown when [rangeWidensCoverage] is true).
const String kRangeEditWidenTitle = 'Move this cancelled range?';
const String kRangeEditWidenMessage =
    'Dates newly covered by this range lose their reservations and early '
    'check-ins (points reversed). Other dates are not affected.';
const String kRangeEditWidenConfirmLabel = 'Save changes';

/// Confirm copy shown before REMOVING a cancel range outright.
const String kRangeRemoveTitle = 'Remove range cancellation?';
const String kRangeRemoveMessage =
    'This class\'s dates come back on the schedule. Any reservations or '
    'check-ins already removed while the range was active are not restored.';
const String kRangeRemoveConfirmLabel = 'Remove cancellation';
