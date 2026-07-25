/// The stable machine-readable reason a check-in was REJECTED by the backend
/// (a thrown 4xx), as opposed to a gate warning on a recorded one.
///
/// Mirrors the backend `CheckinErrorCode`
/// (`../FastApiBackend/src/checkin/checkin_exceptions.py`), which emits it as a
/// **sibling** key beside the plain-string `detail`:
///
/// ```json
/// {"detail": "Class is not active", "code": "class_inactive"}
/// ```
///
/// **The code is the contract; the prose is not.** `detail` is written for
/// humans and may be reworded freely, so nothing client-side may ever match on
/// it — switch on this enum instead. [unknown] is the resilient fallback so a
/// code this client doesn't recognise (the backend may add one) degrades to
/// generic copy instead of crashing or mislabelling.
///
/// The backend's base-class fallback value `checkin_error` is deliberately not
/// mirrored: no concrete exception declares it, and it would resolve to the
/// same generic copy [unknown] already gives.
enum CheckInErrorCode {
  /// 404 — the class does not exist for this gym.
  classNotFound('class_not_found'),

  /// 400 — the class was deleted.
  classDeleted('class_deleted'),

  /// 400 — the class is PAUSED by the gym.
  classInactive('class_inactive'),

  /// 400 — no occurrence at that slot.
  occurrenceNotFound('occurrence_not_found'),

  /// 400 — that day's occurrence is cancelled.
  occurrenceCancelled('occurrence_cancelled'),

  /// 400 — check-in opens 2h before the class starts.
  checkinNotOpen('checkin_not_open'),

  /// 400 — the occurrence is at capacity.
  classFull('class_full'),

  /// A code this client doesn't recognise (forward compatibility).
  unknown('unknown');

  const CheckInErrorCode(this.value);

  final String value;

  /// Resolve a wire value, falling back to [unknown] for anything unrecognised.
  static CheckInErrorCode fromValue(String value) {
    return CheckInErrorCode.values.firstWhere(
      (c) => c.value == value,
      orElse: () => CheckInErrorCode.unknown,
    );
  }

  /// Read the code off a decoded error body (`ServerException.data`).
  ///
  /// Returns null when there is nothing to read — a null body, an absent or
  /// null `code`, or a `code` that isn't a String — so the caller can tell
  /// "no code was sent" (a foreign 400, a 5xx, a network failure) apart from
  /// [unknown] ("a code was sent that we don't know"). Both land on the same
  /// generic copy, but the distinction keeps the parse honest.
  static CheckInErrorCode? fromErrorBody(Map<String, dynamic>? data) {
    final raw = data?['code'];
    return raw is String ? fromValue(raw) : null;
  }
}
