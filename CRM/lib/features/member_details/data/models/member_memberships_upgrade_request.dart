import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/proration_behavior.dart';

part 'member_memberships_upgrade_request.g.dart';

/// Body for `POST /api/v1/member_memberships/upgrade` and its
/// `/upgrade/preview` counterpart (the CROSS-PLAN upgrade).
///
/// Moves the membership to [targetPlanId]'s current active price and
/// charges the prorated DIFFERENCE now when [prorationBehavior] is
/// [ProrationBehavior.prorateToAnchor] and the new price is higher; a
/// downgrade/equal charges nothing. One model serves both the commit and
/// the preview — the preview endpoint simply ignores the extra
/// [idempotencyKey].
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MemberMembershipsUpgradeRequest extends Equatable {
  final String itemId;
  final String memberId;
  final String targetPlanId;
  final ProrationBehavior prorationBehavior;
  final String idempotencyKey;

  const MemberMembershipsUpgradeRequest({
    required this.itemId,
    required this.memberId,
    required this.targetPlanId,
    required this.idempotencyKey,
    this.prorationBehavior = ProrationBehavior.prorateToAnchor,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsUpgradeRequestToJson(this);

  @override
  @JsonKey(includeToJson: false)
  List<Object?> get props => [
        itemId,
        memberId,
        targetPlanId,
        prorationBehavior,
        idempotencyKey,
      ];

  @override
  @JsonKey(includeToJson: false)
  bool? get stringify => super.stringify;

  @override
  @JsonKey(includeToJson: false)
  int get hashCode => super.hashCode; // ignore: hash_and_equals
}
