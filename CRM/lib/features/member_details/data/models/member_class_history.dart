import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_class_history.g.dart';

/// How a member relates to one occurrence in their class history.
///
/// Mirrors the backend `MemberClassHistoryStatus`
/// (`../FastApiBackend/src/checkin/schema/checkin_history_schema.py`).
/// [unknown] is the resilient fallback so a new backend status never
/// crashes the history card.
@JsonEnum(valueField: 'value')
enum MemberClassHistoryStatus {
  reserved('reserved', 'Reserved'),
  attended('attended', 'Attended'),
  noShow('no_show', 'No-show'),
  unknown('unknown', 'Unknown');

  const MemberClassHistoryStatus(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static MemberClassHistoryStatus fromJson(String value) {
    return MemberClassHistoryStatus.values.firstWhere(
      (v) => v.value == value,
      orElse: () => MemberClassHistoryStatus.unknown,
    );
  }

  String toJson() => value;
}

/// One occurrence in a member's class history — either an open
/// reservation ([MemberDetailGrid]'s "Upcoming" block) or a resolved
/// attended/no-show row ("History" block).
///
/// Mirrors the backend `MemberClassHistoryRow`. [originalDate] +
/// [originalTime] are the occurrence's IDENTITY slot (its display date/time
/// — there is no separate "effective" pair here, unlike the schedule
/// board). [durationMinutes] is the class's length (the current schedule
/// version's), so the row can render a start–end time range.
/// [occurredAt] is the attendance row's UTC start instant, set only
/// for [MemberClassHistoryStatus.attended] rows.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberClassHistoryRow extends Equatable {
  final String classId;
  final String className;
  final String? imageUrl;
  final DateTime originalDate;
  final String originalTime;
  final int durationMinutes;
  final DateTime? occurredAt;
  @JsonKey(fromJson: MemberClassHistoryStatus.fromJson)
  final MemberClassHistoryStatus status;

  const MemberClassHistoryRow({
    required this.classId,
    required this.className,
    this.imageUrl,
    required this.originalDate,
    required this.originalTime,
    required this.durationMinutes,
    this.occurredAt,
    required this.status,
  });

  factory MemberClassHistoryRow.fromJson(Map<String, dynamic> json) =>
      _$MemberClassHistoryRowFromJson(json);

  @override
  List<Object?> get props => [
        classId,
        className,
        imageUrl,
        originalDate,
        originalTime,
        durationMinutes,
        occurredAt,
        status,
      ];
}

/// Response for `GET /api/v1/checkin/history?member_id=&gym_id=&limit=&offset=`
/// — the member-page class-history card's feed.
///
/// [upcoming] is every open reservation, soonest first, always complete
/// (unpaginated). [history] is attended + no-show rows, newest first,
/// paginated by the request's `limit`/`offset`; [hasMore] says whether
/// another page of [history] exists.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberClassHistoryResponse extends Equatable {
  @JsonKey(defaultValue: [])
  final List<MemberClassHistoryRow> upcoming;
  @JsonKey(defaultValue: [])
  final List<MemberClassHistoryRow> history;
  final bool hasMore;

  const MemberClassHistoryResponse({
    this.upcoming = const [],
    this.history = const [],
    required this.hasMore,
  });

  factory MemberClassHistoryResponse.fromJson(Map<String, dynamic> json) =>
      _$MemberClassHistoryResponseFromJson(json);

  @override
  List<Object?> get props => [upcoming, history, hasMore];
}
