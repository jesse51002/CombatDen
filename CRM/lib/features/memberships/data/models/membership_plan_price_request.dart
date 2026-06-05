import 'package:json_annotation/json_annotation.dart';

part 'membership_plan_price_request.g.dart';

/// Body for `POST /api/v1/membership_plans/price` — sets a
/// new active price (minor units / cents) for a plan. Existing
/// members keep their old price until migrated.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MembershipPlanPriceRequest {
  final String planId;
  final String gymId;
  final int price;

  const MembershipPlanPriceRequest({
    required this.planId,
    required this.gymId,
    required this.price,
  });

  Map<String, dynamic> toJson() =>
      _$MembershipPlanPriceRequestToJson(this);
}
