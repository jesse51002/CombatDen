import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'member_memberships_update_price_request.g.dart';

/// Body for `PUT /api/v1/member_memberships/price` and
/// its `/price/preview` counterpart.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
)
class MemberMembershipsUpdatePriceRequest extends Equatable {
  final String itemId;
  final String crmUserId;
  final String newPriceId;
  final bool prorate;
  final String idempotencyKey;

  const MemberMembershipsUpdatePriceRequest({
    required this.itemId,
    required this.crmUserId,
    required this.newPriceId,
    required this.idempotencyKey,
    this.prorate = false,
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsUpdatePriceRequestToJson(this);

  @override
  List<Object?> get props => [
        itemId,
        crmUserId,
        newPriceId,
        prorate,
        idempotencyKey,
      ];
}
