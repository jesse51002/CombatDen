/// Why the backend refused a reservation, keyed by its stable machine-readable
/// `code`.
///
/// Mirrors the reservation subset of `CheckinErrorCode` in
/// `FastApiBackend/src/checkin/checkin_exceptions.py`. The backend puts the
/// code on the wire as a SIBLING of `detail`
/// (`{"detail": "Class is full", "code": "class_full"}`) and states that the
/// exception TYPE — not the message text — is the source of truth for both the
/// status and the code. So this is the ONE place a rejection is classified;
/// nothing anywhere else may read the prose to decide what happened.
///
/// `CheckinErrorCode` also carries `checkin_not_open` (check-in only, a
/// reservation is never rejected for it) and `checkin_error` (the base's
/// fallback, which no concrete exception uses). Both correctly land on
/// [unknown] here, as does any code added to the backend later — new codes are
/// additive by contract, so an unmapped one must degrade to the backend's own
/// `detail` rather than to a wrong message.
enum BookingRejection {
  /// The occurrence is at its effective capacity.
  classFull('class_full', 'This class is full. Try another time.'),

  /// The slot IS an occurrence of the class, but that day is cancelled.
  occurrenceCancelled(
    'occurrence_cancelled',
    'This class is cancelled that day.',
  ),

  /// The class is paused (`is_active` false).
  classInactive('class_inactive', 'This class is not running right now.'),

  /// The class is soft-deleted.
  classDeleted('class_deleted', 'This class is no longer on the schedule.'),

  /// The addressed `(date, time)` is not an occurrence of this class — the
  /// schedule moved under a board the member is still looking at.
  occurrenceNotFound(
    'occurrence_not_found',
    'This class is not scheduled at that time anymore.',
  ),

  /// No such class for this gym.
  classNotFound('class_not_found', 'We cannot find this class anymore.'),

  /// No code on the wire, or a code this build does not know. Carries no copy
  /// — the caller falls back to the backend's `detail`, then to a generic
  /// message, so a rejection is never blank.
  unknown(null, null);

  const BookingRejection(this.code, this.memberMessage);

  /// The wire value. Null for [unknown], which is not a wire value.
  final String? code;

  /// Member-facing copy for this rejection. The raw `detail` is written for
  /// engineers ("Not a class occurrence on that date"), so every code we know
  /// gets plain language instead. Null for [unknown] only.
  final String? memberMessage;

  /// Resolve a wire code. An absent or unrecognised code is [unknown] — never
  /// a throw, never a wrong match (the enum rule: every value parsed from the
  /// backend has a safe fallback).
  static BookingRejection fromCode(String? code) {
    if (code == null || code.isEmpty) return unknown;
    return values.firstWhere(
      (r) => r.code == code,
      orElse: () => unknown,
    );
  }
}
