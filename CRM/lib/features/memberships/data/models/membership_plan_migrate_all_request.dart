import 'package:json_annotation/json_annotation.dart';

part 'membership_plan_migrate_all_request.g.dart';

/// Body for `POST /api/v1/membership_plans/migrate-all` — moves every
/// member still on an older price onto the plan's current active price
/// (a background bulk payment sync).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MembershipPlanMigrateAllRequest {
  final String planId;
  final String gymId;

  const MembershipPlanMigrateAllRequest({
    required this.planId,
    required this.gymId,
  });

  Map<String, dynamic> toJson() =>
      _$MembershipPlanMigrateAllRequestToJson(this);
}
