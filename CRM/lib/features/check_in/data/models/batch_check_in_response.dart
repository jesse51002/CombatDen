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

  bool get hasFailures => failed.isNotEmpty;

  @override
  List<Object?> get props =>
      [classId, occurrenceDate, classHistoryId, results];
}
