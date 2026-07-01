import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/check_in/data/models/batch_check_in_result_item.dart';

part 'batch_check_in_response.g.dart';

/// Response body for the batch check-in (returned with 207 Multi-Status —
/// a 2xx, so it lands on the success path, not as an exception).
///
/// Mirrors the backend `BatchCheckinResponse`. [classHistoryId] is the single
/// materialized occurrence every member was checked into; [results] is one item
/// per (de-duped) member, in request order.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class BatchCheckInResponse extends Equatable {
  final String classId;

  /// The local calendar date (`YYYY-MM-DD`) checked in — the PATH param echoed
  /// back. Kept as the raw string (the board renders the date itself).
  final String occurrenceDate;
  final String classHistoryId;
  @JsonKey(defaultValue: [])
  final List<BatchCheckInResultItem> results;

  const BatchCheckInResponse({
    required this.classId,
    required this.occurrenceDate,
    required this.classHistoryId,
    this.results = const [],
  });

  factory BatchCheckInResponse.fromJson(Map<String, dynamic> json) =>
      _$BatchCheckInResponseFromJson(json);

  /// Newly-recorded attendance rows (excludes already-checked-in repeats).
  int get checkedInCount =>
      results.where((r) => r.status.isCheckedIn).length;

  List<BatchCheckInResultItem> get failed =>
      results.where((r) => r.status.isFailed).toList();

  /// Members the gate warned on and held for confirmation — nothing written
  /// for these. Resend a batch of just their ids with `ignore_warnings: true`
  /// (the "Check in anyway" override) to record them.
  List<BatchCheckInResultItem> get needsConfirmation =>
      results.where((r) => r.status.isNeedsConfirmation).toList();

  bool get hasFailures => failed.isNotEmpty;

  /// Merge a confirmation retry's response — covering only the subset of
  /// members resubmitted with `ignore_warnings: true` — back into this full
  /// result set, replacing each resubmitted member's row in place while
  /// leaving every other member's outcome untouched.
  BatchCheckInResponse mergeConfirmed(BatchCheckInResponse retry) {
    final updates = {for (final r in retry.results) r.memberId: r};
    return BatchCheckInResponse(
      classId: classId,
      occurrenceDate: occurrenceDate,
      classHistoryId: classHistoryId,
      results: results.map((r) => updates[r.memberId] ?? r).toList(),
    );
  }

  @override
  List<Object?> get props =>
      [classId, occurrenceDate, classHistoryId, results];
}
