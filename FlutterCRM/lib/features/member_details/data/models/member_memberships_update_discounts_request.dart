import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_update_discounts_request.g.dart';

/// Body for `PUT /api/v1/member_memberships/discounts`
/// and `POST /api/v1/member_memberships/discounts/preview`.
///
/// Replaces the full discount set for a given membership.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MemberMembershipsUpdateDiscountsRequest
    extends Equatable {
  final String itemId;
  final String crmUserId;
  final List<String> discountIds;
  final String idempotencyKey;

  const MemberMembershipsUpdateDiscountsRequest({
    required this.itemId,
    required this.crmUserId,
    required this.discountIds,
    required this.idempotencyKey,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsUpdateDiscountsRequestToJson(this);

  @override
  List<Object?> get props => [
        itemId,
        crmUserId,
        discountIds,
        idempotencyKey,
      ];
}
