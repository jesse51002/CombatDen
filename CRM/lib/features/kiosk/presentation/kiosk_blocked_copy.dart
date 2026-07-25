import 'package:crm/features/check_in/data/models/check_in_error_code.dart';
import 'package:crm/features/check_in/data/models/check_in_warning.dart';

/// The blocked screen's one-line "WHY" copy. Two sources feed it: a gate
/// rejection (HTTP 200 with a `skip_reason` — [CheckInWarning]) and a failed
/// call (a thrown error carrying the backend's stable [CheckInErrorCode]).
///
/// **Never match on the `detail` prose** — the backend may reword it at will;
/// the `code` is the contract. Every line is blame-free and stops at the fact,
/// since the screen itself supplies the front-desk handoff; anything
/// unrecognised — unknown code, foreign 400, 5xx, dropped network — lands on
/// the same calm generic line.
///
/// The overdue line is deliberately discreet: this screen faces a LOBBY with a
/// queue behind it, so it is read by people who are not the member. "A billing
/// detail" still names the domain — bring a card to the desk — without
/// publishing to a room that they are behind on money. Do not "clarify" it
/// back to "overdue" or "unpaid" (the staff-side label rightly is).
String kioskBlockedCopy({
  CheckInWarning? reason,
  bool failed = false,
  CheckInErrorCode? code,
}) {
  if (failed) return _failureCopy(code);
  return switch (reason) {
    CheckInWarning.overCapacity => 'This class is full.',
    CheckInWarning.noMembership => 'We couldn\'t find an active membership.',
    CheckInWarning.outOfClasses => 'You\'re out of classes on your plan.',
    CheckInWarning.ineligiblePlan => 'Your plan doesn\'t include this class.',
    CheckInWarning.unsignedWaiver => 'There\'s a waiver to sign.',
    CheckInWarning.overdue => 'There\'s a billing detail to sort out.',
    CheckInWarning.unknown || null => 'Let\'s get you checked in at the desk.',
  };
}

/// A thrown resolution error, keyed on the backend's machine-readable code.
String _failureCopy(CheckInErrorCode? code) {
  return switch (code) {
    CheckInErrorCode.classFull => 'This class is full.',
    CheckInErrorCode.classInactive ||
    CheckInErrorCode.classDeleted =>
      'This class isn\'t running right now.',
    CheckInErrorCode.checkinNotOpen =>
      'Check-in opens a little before the class starts.',
    CheckInErrorCode.occurrenceCancelled => 'This class is cancelled today.',
    CheckInErrorCode.classNotFound ||
    CheckInErrorCode.occurrenceNotFound =>
      'That class isn\'t available right now.',
    CheckInErrorCode.unknown ||
    null =>
      'We couldn\'t complete your check-in just now.',
  };
}
