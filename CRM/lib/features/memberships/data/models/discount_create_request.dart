import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';

part 'discount_create_request.g.dart';

/// Body for `POST /api/v1/discounts/` — a coupon-free discount
/// preset. Exactly one of [percentageOff] / [dollarOff] is set;
/// for an `ongoing` [discountMode], the lifetime is a duration
/// span (amount + unit) XOR an explicit [endDate], or neither
/// (forever). [dollarOff] is in minor units (cents).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class DiscountCreateRequest {
  final String gymId;
  final String discountName;
  final DiscountType discountType;
  final double? percentageOff;
  final int? dollarOff;
  final DiscountMode discountMode;
  final int? durationAmount;
  final DiscountDurationUnit? durationUnit;
  @JsonKey(toJson: _dateToJson)
  final DateTime? endDate;

  const DiscountCreateRequest({
    required this.gymId,
    required this.discountName,
    this.discountType = DiscountType.preset,
    this.percentageOff,
    this.dollarOff,
    required this.discountMode,
    this.durationAmount,
    this.durationUnit,
    this.endDate,
  });

  static String? _dateToJson(DateTime? d) =>
      d?.toIso8601String().split('T').first;

  Map<String, dynamic> toJson() =>
      _$DiscountCreateRequestToJson(this);
}
