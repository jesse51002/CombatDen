import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/duration_unit.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

part 'membership_plan_response.g.dart';

/// A gym's membership plan, returned by
/// `GET /api/v1/membership_plans/?gym_id=…`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembershipPlanResponse extends Equatable {
  final String planId;
  final String gymId;
  final String planName;
  @JsonKey(fromJson: PlanType.fromJson)
  final PlanType planType;
  final int? classCount;
  final int? durationAmount;
  @JsonKey(fromJson: _durationUnitFromJson)
  final DurationUnit? durationUnit;
  final bool isPublic;
  final String? stripeProductId;
  final DateTime createdAt;
  final MembershipPlanPriceResponse? activePrice;

  /// Count of active memberships on this plan. Populated by
  /// the list endpoint; defaults to 0 when absent (e.g. the
  /// single-plan get, or an older backend).
  @JsonKey(defaultValue: 0)
  final int enrolledCount;

  /// Waiver ids a member must sign for this plan (multi-select).
  @JsonKey(defaultValue: <String>[])
  final List<String> waiverIds;

  const MembershipPlanResponse({
    required this.planId,
    required this.gymId,
    required this.planName,
    required this.planType,
    this.classCount,
    this.durationAmount,
    this.durationUnit,
    required this.isPublic,
    this.stripeProductId,
    required this.createdAt,
    this.activePrice,
    this.enrolledCount = 0,
    this.waiverIds = const [],
  });

  factory MembershipPlanResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MembershipPlanResponseFromJson(json);

  static DurationUnit? _durationUnitFromJson(
    String? value,
  ) =>
      value == null ? null : DurationUnit.fromJson(value);

  @override
  List<Object?> get props => [
        planId,
        gymId,
        planName,
        planType,
        classCount,
        durationAmount,
        durationUnit,
        isPublic,
        stripeProductId,
        createdAt,
        activePrice,
        enrolledCount,
        waiverIds,
      ];
}
