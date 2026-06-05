import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';

part 'discount_update_request.g.dart';

/// Mutable preset fields for `PUT /api/v1/discounts/`. Only
/// non-null fields are sent. [dollarOff] is in minor units.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class DiscountUpdateData {
  final String? discountName;
  final double? percentageOff;
  final int? dollarOff;
  final DiscountMode? discountMode;
  final int? durationAmount;
  final DiscountDurationUnit? durationUnit;
  @JsonKey(toJson: _dateToJson)
  final DateTime? endDate;

  const DiscountUpdateData({
    this.discountName,
    this.percentageOff,
    this.dollarOff,
    this.discountMode,
    this.durationAmount,
    this.durationUnit,
    this.endDate,
  });

  static String? _dateToJson(DateTime? d) =>
      d?.toIso8601String().split('T').first;

  Map<String, dynamic> toJson() =>
      _$DiscountUpdateDataToJson(this);
}

/// Body for `PUT /api/v1/discounts/` — identity fields plus a
/// nested [data] of changes.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  explicitToJson: true,
  createFactory: false,
)
class DiscountUpdateRequest {
  final String discountId;
  final String gymId;
  final DiscountUpdateData data;

  const DiscountUpdateRequest({
    required this.discountId,
    required this.gymId,
    required this.data,
  });

  Map<String, dynamic> toJson() =>
      _$DiscountUpdateRequestToJson(this);
}
