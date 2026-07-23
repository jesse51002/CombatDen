import 'package:json_annotation/json_annotation.dart';

part 'class_history.g.dart';

/// How a member relates to one occurrence in their class history.
///
/// Mirrors `MemberClassHistoryStatus` in
/// `FastApiBackend/src/checkin/schema/checkin_history_schema.py`. An unknown
/// backend value parses to [unknown] rather than crashing the feed.
enum MemberClassHistoryStatus {
  @JsonValue('reserved')
  reserved,
  @JsonValue('attended')
  attended,
  @JsonValue('no_show')
  noShow,
  unknown,
}

/// One occurrence in a member's class history (a reservation, an attended
/// class, or a no-show).
///
/// Mirrors `MemberClassHistoryRow` in
/// `FastApiBackend/src/checkin/schema/checkin_history_schema.py`. Date/time
/// fields stay raw ISO strings — an open reservation's
/// `(class_id, original_date, original_time)` is the key the board joins on and
/// the cancel call echoes back VERBATIM.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberClassHistoryRow {
  final String classId;
  final String className;

  /// The class image. Never null on the backend row.
  final String imageUrl;
  final String originalDate;
  final String originalTime;
  final int durationMinutes;

  /// Points this class was worth — the "+N points" the post-class celebration
  /// count-up rolls to for an attended row. Mirrors the `points_worth` column
  /// added to each history row. Defaults to 0 when a row omits it (the column
  /// is being rolled out concurrently), so parsing the shared
  /// reservations/history feed never breaks on an older backend.
  @JsonKey(defaultValue: 0)
  final int pointsWorth;

  /// The attendance row's start instant — attended rows only (null otherwise).
  final String? occurredAt;

  @JsonKey(unknownEnumValue: MemberClassHistoryStatus.unknown)
  final MemberClassHistoryStatus status;

  const MemberClassHistoryRow({
    required this.classId,
    required this.className,
    required this.imageUrl,
    required this.originalDate,
    required this.originalTime,
    required this.durationMinutes,
    required this.status,
    this.pointsWorth = 0,
    this.occurredAt,
  });

  /// The reservation's slot key — matches [ClassOccurrence.slotKey] so the
  /// board can mark an occurrence `booked`.
  String get slotKey => '$classId|$originalDate|$originalTime';

  factory MemberClassHistoryRow.fromJson(Map<String, dynamic> json) =>
      _$MemberClassHistoryRowFromJson(json);
}

/// The member's class-history feed: open reservations plus paginated
/// attended / no-show history.
///
/// Mirrors `MemberClassHistoryResponse` in
/// `FastApiBackend/src/checkin/schema/checkin_history_schema.py`.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberClassHistory {
  /// Open reservations (occurrences not yet ended), soonest first, unpaginated.
  final List<MemberClassHistoryRow> upcoming;

  /// Attended + no-show rows, newest first (paginated).
  final List<MemberClassHistoryRow> history;
  final bool hasMore;

  const MemberClassHistory({
    required this.upcoming,
    required this.history,
    required this.hasMore,
  });

  factory MemberClassHistory.fromJson(Map<String, dynamic> json) =>
      _$MemberClassHistoryFromJson(json);
}
