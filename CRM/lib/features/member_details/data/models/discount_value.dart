import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';

part 'discount_value.g.dart';

/// One discount value version — everything that determines the
/// discount (how much, mode, how long).
///
/// Mirrors `DiscountValue` from the backend:
/// - Exactly one of [percentageOff] / [dollarOff] is set.
/// - [discountMode] is `once` or `ongoing`.
/// - Lifetime is a duration span ([durationAmount] +
///   [durationUnit]) XOR an explicit [endDate] — never both;
///   neither means forever.
/// - [dollarOff] is in minor units (cents).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
)
class DiscountValue extends Equatable {
  final double? percentageOff;
  final int? dollarOff;
  @JsonKey(fromJson: DiscountMode.fromJson)
  final DiscountMode discountMode;
  final int? durationAmount;
  @JsonKey(fromJson: _durationUnitOrNull)
  final DiscountDurationUnit? durationUnit;
  @JsonKey(toJson: _dateToJson)
  final DateTime? endDate;

  const DiscountValue({
    this.percentageOff,
    this.dollarOff,
    required this.discountMode,
    this.durationAmount,
    this.durationUnit,
    this.endDate,
  });

  factory DiscountValue.fromJson(Map<String, dynamic> json) =>
      _$DiscountValueFromJson(json);

  Map<String, dynamic> toJson() => _$DiscountValueToJson(this);

  static DiscountDurationUnit? _durationUnitOrNull(Object? value) =>
      value == null
          ? null
          : DiscountDurationUnit.fromJson(value as String);

  /// Date-only ISO string for the backend — `YYYY-MM-DD`.
  static String? _dateToJson(DateTime? d) =>
      d?.toIso8601String().split('T').first;

  @override
  List<Object?> get props => [
        percentageOff,
        dollarOff,
        discountMode,
        durationAmount,
        durationUnit,
        endDate,
      ];
}
