import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/proration_behavior.dart';

part 'member_memberships_update_price_request.g.dart';

/// Body for `PUT /api/v1/member_memberships/price` and
/// its `/price/preview` counterpart.
///
/// Matches the merged `MemberMembershipsUpdatePriceRequest`
/// schema (member-id keyed). NOTE: the merged contract
/// migrates the membership to the plan's current active
/// price and therefore does NOT accept a target price id
/// — the pre-merge `new_price_id` field was dropped.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MemberMembershipsUpdatePriceRequest extends Equatable {
  final String itemId;
  final String memberId;
  final ProrationBehavior prorationBehavior;
  final String idempotencyKey;

  const MemberMembershipsUpdatePriceRequest({
    required this.itemId,
    required this.memberId,
    required this.idempotencyKey,
    this.prorationBehavior = ProrationBehavior.noCharge,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsUpdatePriceRequestToJson(this);

  @override
  @JsonKey(includeToJson: false)
  List<Object?> get props => [
        itemId,
        memberId,
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
