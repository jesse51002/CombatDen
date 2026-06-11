import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';

part 'discount_create_request.g.dart';

/// Body for `POST /api/v1/discounts/` — a coupon-free discount
/// preset. [value] carries the complete discount spec (amount,
/// mode, and lifetime). [dollarOff] inside [value] is in minor
/// units (cents).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  explicitToJson: true,
  createFactory: false,
)
class DiscountCreateRequest {
  final String gymId;
  final String discountName;
  final DiscountType discountType;
  final DiscountValue value;

  const DiscountCreateRequest({
    required this.gymId,
    required this.discountName,
    this.discountType = DiscountType.preset,
    required this.value,
  });

  Map<String, dynamic> toJson() =>
      _$DiscountCreateRequestToJson(this);
}
