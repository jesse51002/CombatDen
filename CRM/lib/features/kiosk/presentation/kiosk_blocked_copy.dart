import 'package:crm/features/check_in/data/models/check_in_error_code.dart';
import 'package:crm/features/check_in/data/models/check_in_warning.dart';

/// The blocked screen's one-line "WHY" copy.
///
/// Two sources feed it, and they are different shapes:
/// * a **gate rejection** — HTTP 200 with a `skip_reason` ([CheckInWarning]);
/// * a **failed call** — a thrown error carrying the backend's stable
///   [CheckInErrorCode] (the `code` sibling of `detail`).
///
/// **Never match on the `detail` prose.** The backend states plainly that the
/// message text is for humans and may be reworded at will, while the `code` is
/// the contract — matching on prose here would recreate exactly the fragility
/// the typed backend errors removed.
///
/// Every line is blame-free and stops at the fact: the screen itself supplies
/// the front-desk handoff ("Nothing's wrong. The coach at the desk can sort
/// it…"), so no line here may carry an error code, jargon, or any hint the
/// member did something wrong. Anything unrecognised — an unknown code, a
/// foreign 400, a 5xx, a dropped network — lands on the same calm generic line.
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
