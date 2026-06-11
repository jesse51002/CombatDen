import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

part 'member_memberships_start_result_item.g.dart';

/// Per-membership outcome in the start breakdown.
///
/// Mirrors the backend `MemberMembershipsStartResultItem`:
/// [itemId] is set when `status = created`; [error] carries
/// the failure reason when `status = failed`. Failure
/// granularity is the charge group (the one-time invoice /
/// the recurring converge), so same-group items share fate.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MemberMembershipsStartResultItem extends Equatable {
  final String memberId;
  final String planId;
  @JsonKey(fromJson: PlanType.fromJson)
  final PlanType planType;
  @JsonKey(fromJson: MemberMembershipsStartStatus.fromJson)
  final MemberMembershipsStartStatus status;
  final String? itemId;
  final String? error;

  const MemberMembershipsStartResultItem({
    required this.memberId,
    required this.planId,
    required this.planType,
    required this.status,
    this.itemId,
    this.error,
  });

  factory MemberMembershipsStartResultItem.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberMembershipsStartResultItemFromJson(json);

  bool get isCreated =>
      status == MemberMembershipsStartStatus.created;

  bool get isFailed =>
      status == MemberMembershipsStartStatus.failed;

  @override
  List<Object?> get props => [
        memberId,
        planId,
        planType,
        status,
        itemId,
        error,
      ];
}
