import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/duration_unit.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

part 'membership_plan_update_request.g.dart';

/// Mutable plan fields for `PUT /api/v1/membership_plans/`.
/// Only non-null fields are sent (the backend leaves the
/// rest unchanged). Price changes go through the dedicated
/// `POST /price` endpoint, not here.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class MembershipPlanUpdateData {
  final String? planName;
  final PlanType? planType;
  final int? classCount;
  final int? durationAmount;
  final DurationUnit? durationUnit;
  final bool? isPublic;
  final List<String>? waiverIds;
  final bool? linkedDiscountEnabled;
  final List<int>? linkedDiscountPrices;

  const MembershipPlanUpdateData({
    this.planName,
    this.planType,
    this.classCount,
    this.durationAmount,
    this.durationUnit,
    this.isPublic,
    this.waiverIds,
    this.linkedDiscountEnabled,
    this.linkedDiscountPrices,
  });

  Map<String, dynamic> toJson() =>
      _$MembershipPlanUpdateDataToJson(this);
}

/// Body for `PUT /api/v1/membership_plans/` — identity fields
/// plus a nested [data] of changes.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  explicitToJson: true,
  createFactory: false,
)
class MembershipPlanUpdateRequest {
  final String planId;
  final String gymId;
  final MembershipPlanUpdateData data;

  const MembershipPlanUpdateRequest({
    required this.planId,
    required this.gymId,
    required this.data,
  });

  Map<String, dynamic> toJson() =>
      _$MembershipPlanUpdateRequestToJson(this);
}
