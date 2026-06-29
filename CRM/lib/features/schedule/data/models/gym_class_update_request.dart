import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/schedule/data/models/recurring_unit.dart';

part 'gym_class_update_request.g.dart';

/// Mutable fields for `PUT /api/v1/classes/{class_id}` — every field optional.
///
/// Tracks the backend `GymClassUpdateData`. `includeIfNull: false` means a
/// null field is **omitted** (left unchanged), so the form sends only the
/// values it has. The backend keys its change set off the fields present in
/// the body, validating them against the `GYM_CLASSES` immutable guard.
///
/// Note: because nulls are omitted, an optional field cannot be *cleared* back
/// to null through this path (the same trade-off the membership-plan update
/// model makes). Clearing a nullable column would need an explicit-null /
/// sentinel design — flagged, not built here.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  includeIfNull: false,
  explicitToJson: true,
)
class GymClassUpdateData {
  final String? className;
  final String? classDescription;

  /// Local start time of day as `HH:MM:SS`.
  final String? classTime;
  final int? durationMinutes;
  final RecurringUnit? recurringUnit;
  final int? recurringInterval;
  final bool? sun;
  final bool? mon;
  final bool? tue;
  final bool? wed;
  final bool? thu;
  final bool? fri;
  final bool? sat;
  final String? sunInstructorId;
  final String? monInstructorId;
  final String? tueInstructorId;
  final String? wedInstructorId;
  final String? thuInstructorId;
  final String? friInstructorId;
  final String? satInstructorId;

  /// `YYYY-MM-DD`.
  final String? startDate;

  /// `YYYY-MM-DD`.
  final String? endDate;
  final int? maxCapacity;
  final List<String>? allowedPlanIds;
  final String? imageUrl;
  final int? pointsWorth;

  const GymClassUpdateData({
    this.className,
    this.classDescription,
    this.classTime,
    this.durationMinutes,
    this.recurringUnit,
    this.recurringInterval,
    this.sun,
    this.mon,
    this.tue,
    this.wed,
    this.thu,
    this.fri,
    this.sat,
    this.sunInstructorId,
    this.monInstructorId,
    this.tueInstructorId,
    this.wedInstructorId,
    this.thuInstructorId,
    this.friInstructorId,
    this.satInstructorId,
    this.startDate,
    this.endDate,
    this.maxCapacity,
    this.allowedPlanIds,
    this.imageUrl,
    this.pointsWorth,
  });

  Map<String, dynamic> toJson() => _$GymClassUpdateDataToJson(this);
}

/// Body for `PUT /api/v1/classes/{class_id}` — the class id rides the URL path,
/// the changes nest under [data].
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  explicitToJson: true,
)
class GymClassUpdateRequest {
  final GymClassUpdateData data;

  const GymClassUpdateRequest({required this.data});

  Map<String, dynamic> toJson() => _$GymClassUpdateRequestToJson(this);
}
