import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'class_slot.g.dart';

/// One `(time, instructor)` slot inside a schedule's `weekday_slots` map.
///
/// Tracks the backend `ClassSlot` (request) / `ClassSlotResponse` (response)
/// (`../FastApiBackend/src/classes/schema/classes_crud_schema.py`,
/// `classes_expander_schema.py`) — the SAME slot shape serves both requests
/// and responses, since the only difference is [instructorName]: a request
/// never sets it (`includeIfNull: false` omits it from the wire body, so the
/// backend's request schema — which has no such field — never sees it), a
/// response always carries it (resolved `first_name last_name`, null when the
/// slot has no instructor or the employee is gone).
///
/// [time] is `HH:MM:SS` (gym-local; render as given, no timezone math) — the
/// occurrence's identity time together with the owning day/date.
@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class ClassSlot extends Equatable {
  final String time;
  final String? instructorId;

  /// Response-only: never set when building a request slot.
  final String? instructorName;

  const ClassSlot({
    required this.time,
    this.instructorId,
    this.instructorName,
  });

  factory ClassSlot.fromJson(Map<String, dynamic> json) =>
      _$ClassSlotFromJson(json);

  Map<String, dynamic> toJson() => _$ClassSlotToJson(this);

  @override
  List<Object?> get props => [time, instructorId, instructorName];
}
