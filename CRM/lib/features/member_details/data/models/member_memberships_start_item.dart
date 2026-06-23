import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_value.dart';

part 'member_memberships_start_item.g.dart';

/// One membership to create inside a start request.
///
/// Mirrors the backend `MemberMembershipsStartItem`:
/// [priceId] alone identifies what is bought (a price
/// belongs to exactly one plan, derived server-side).
/// [quantity] is how many units this one item buys — a
/// one_time / trial pack bought N at once is ONE item with
/// `quantity = N` (not N items); recurring stays 1.
/// [discountIds] reference existing preset / linked
/// discounts; [customDiscounts] are inline values minted
/// server-side as one-shot `custom` discounts. Both land
/// before the first charge.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  explicitToJson: true,
)
class MemberMembershipsStartItem extends Equatable {
  final String memberId;
  final String priceId;
  final int quantity;
  final List<String> discountIds;
  final List<DiscountValue> customDiscounts;

  const MemberMembershipsStartItem({
    required this.memberId,
    required this.priceId,
    this.quantity = 1,
    this.discountIds = const [],
    this.customDiscounts = const [],
  });

  Map<String, dynamic> toJson() =>
      _$MemberMembershipsStartItemToJson(this);

  @override
  List<Object?> get props => [
        memberId,
        priceId,
        quantity,
        discountIds,
        customDiscounts,
      ];
}
