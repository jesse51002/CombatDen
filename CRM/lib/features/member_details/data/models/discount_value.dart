import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';

part 'discount_value.g.dart';

/// One discount value version — everything that determines the
/// discount (how much, how long).
///
/// Mirrors `DiscountValue` from the backend:
/// - Exactly one of [percentageOff] / [dollarOff] is set.
/// - Lifetime is a duration span ([durationAmount] +
///   [durationUnit]) XOR an explicit [endDate] — never both;
///   neither means forever. A 1-`cycle` span is the
///   single-invoice discount that replaced the old `once`
///   mode.
/// - [dollarOff] is in minor units (cents).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
)
class DiscountValue extends Equatable {
  final double? percentageOff;
  final int? dollarOff;
  final int? durationAmount;
  @JsonKey(fromJson: _durationUnitOrNull)
  final DiscountDurationUnit? durationUnit;
  @JsonKey(toJson: _dateToJson)
  final DateTime? endDate;

  const DiscountValue({
    this.percentageOff,
    this.dollarOff,
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
        durationAmount,
        durationUnit,
        endDate,
      ];
}
