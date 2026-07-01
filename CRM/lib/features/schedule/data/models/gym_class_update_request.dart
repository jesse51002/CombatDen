import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/schedule/data/models/recurring_unit.dart';

part 'gym_class_update_request.g.dart';

/// Mutable IDENTITY fields for `PUT /api/v1/classes/{class_id}` — every field
/// optional. Tracks the backend `GymClassIdentityUpdateData`.
///
/// `includeIfNull: false` means a null field is **omitted** (left unchanged),
/// so the form sends only the values it has. The backend keys its change set
/// off the fields present in the body, validating them against the
/// `GYM_CLASSES` immutable guard. `isDeleted` is deliberately NOT accepted
/// here — deletion only goes through `DELETE /classes/{class_id}`.
///
/// Note: because nulls are omitted, an optional field cannot be *cleared*
/// back to null through this path (the same trade-off the membership-plan
/// update model makes). Clearing a nullable column would need an explicit-null
/// / sentinel design — flagged, not built here.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  includeIfNull: false,
  explicitToJson: true,
)
class GymClassIdentityUpdateData {
  final String? className;
  final String? classDescription;
  final int? maxCapacity;
  final List<String>? allowedPlanIds;
  final String? imageUrl;
  final int? pointsWorth;
  final bool? isActive;

  const GymClassIdentityUpdateData({
    this.className,
    this.classDescription,
    this.maxCapacity,
    this.allowedPlanIds,
    this.imageUrl,
    this.pointsWorth,
    this.isActive,
  });

  Map<String, dynamic> toJson() => _$GymClassIdentityUpdateDataToJson(this);
}

/// The COMPLETE schedule shape for `PUT /api/v1/classes/{class_id}` — tracks
/// the backend `GymClassScheduleFields` field-for-field (the same shape
/// `GymClassCreateRequest` sends flat). Always submitted whole: a schedule
/// edit mints a new `gym_class_schedules` version, never patches one, so
/// every field is required here (no partial schedule update exists).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  explicitToJson: true,
)
class GymClassScheduleFields {
  /// Local start time of day as `HH:MM:SS`.
  final String classTime;
  final int durationMinutes;
  final RecurringUnit recurringUnit;
  final int recurringInterval;
  final bool sun;
  final bool mon;
  final bool tue;
  final bool wed;
  final bool thu;
  final bool fri;
  final bool sat;
  final String? sunInstructorId;
  final String? monInstructorId;
  final String? tueInstructorId;
  final String? wedInstructorId;
  final String? thuInstructorId;
  final String? friInstructorId;
  final String? satInstructorId;

  /// `YYYY-MM-DD`.
  final String startDate;

  /// `YYYY-MM-DD`, optional.
  final String? endDate;

  const GymClassScheduleFields({
    required this.classTime,
    required this.durationMinutes,
    required this.recurringUnit,
    required this.recurringInterval,
    required this.sun,
    required this.mon,
    required this.tue,
    required this.wed,
    required this.thu,
    required this.fri,
    required this.sat,
    this.sunInstructorId,
    this.monInstructorId,
    this.tueInstructorId,
    this.wedInstructorId,
    this.thuInstructorId,
    this.friInstructorId,
    this.satInstructorId,
    required this.startDate,
    this.endDate,
  });

  Map<String, dynamic> toJson() => _$GymClassScheduleFieldsToJson(this);
}

/// Body for `PUT /api/v1/classes/{class_id}` — split by destination:
/// [identity] (partial) updates `gym_classes` in place; [schedule] (a
/// COMPLETE shape) mints a new `gym_class_schedules` version effective now.
/// Either half may be omitted; a [schedule] deep-equal to the current version
/// is a backend no-op (no mint, no wipe). The class form can't always tell
/// which half actually changed, so it sends both every time — sending an
/// unchanged half is safe by design (mirrors the discounts identity/values
/// update split).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  explicitToJson: true,
  includeIfNull: false,
)
class GymClassUpdateRequest {
  final GymClassIdentityUpdateData? identity;
  final GymClassScheduleFields? schedule;

  const GymClassUpdateRequest({this.identity, this.schedule});

  Map<String, dynamic> toJson() => _$GymClassUpdateRequestToJson(this);
}
