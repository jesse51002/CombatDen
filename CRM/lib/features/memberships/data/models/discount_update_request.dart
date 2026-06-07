import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';

part 'discount_update_request.g.dart';

/// Identity changes for `PUT /api/v1/discounts/` — renames the
/// gym_discounts row in place. Only non-null fields are sent.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class DiscountUpdateIdentity {
  final String? discountName;

  const DiscountUpdateIdentity({this.discountName});

  Map<String, dynamic> toJson() =>
      _$DiscountUpdateIdentityToJson(this);
}

/// Value/lifetime changes for `PUT /api/v1/discounts/` — mints a new
/// gym_discount_values version. Only non-null fields are sent.
/// [dollarOff] is in minor units.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class DiscountUpdateValues {
  final double? percentageOff;
  final int? dollarOff;
  final DiscountMode? discountMode;
  final int? durationAmount;
  final DiscountDurationUnit? durationUnit;
  @JsonKey(toJson: _dateToJson)
  final DateTime? endDate;

  const DiscountUpdateValues({
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
      _$DiscountUpdateValuesToJson(this);
}

/// Body for `PUT /api/v1/discounts/` — identity keys plus the
/// destination sub-objects: [identity] (rename) and [values] (new
/// version). At least one must be present.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  explicitToJson: true,
  includeIfNull: false,
  createFactory: false,
)
class DiscountUpdateRequest {
  final String discountId;
  final String gymId;
  final DiscountUpdateIdentity? identity;
  final DiscountUpdateValues? values;

  const DiscountUpdateRequest({
    required this.discountId,
    required this.gymId,
    this.identity,
    this.values,
  });

  Map<String, dynamic> toJson() =>
      _$DiscountUpdateRequestToJson(this);
}
