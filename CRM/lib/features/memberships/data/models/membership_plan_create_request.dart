import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/duration_unit.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

part 'membership_plan_create_request.g.dart';

/// Body for `POST /api/v1/membership_plans/` — creates a plan
/// plus its initial price (`price` in minor units / cents).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MembershipPlanCreateRequest {
  final String gymId;
  final String planName;
  final PlanType planType;
  final int? classCount;
  final int? durationAmount;
  final DurationUnit? durationUnit;
  final bool isPublic;
  final int price;
  final List<String> waiverIds;
  final bool linkedDiscountEnabled;
  final List<int> linkedDiscountPrices;

  const MembershipPlanCreateRequest({
    required this.gymId,
    required this.planName,
    required this.planType,
    this.classCount,
    this.durationAmount,
    this.durationUnit,
    this.isPublic = true,
    required this.price,
    this.waiverIds = const [],
    this.linkedDiscountEnabled = false,
    this.linkedDiscountPrices = const [],
  });

  Map<String, dynamic> toJson() =>
      _$MembershipPlanCreateRequestToJson(this);
}
