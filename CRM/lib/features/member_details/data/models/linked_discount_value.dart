import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'linked_discount_value.g.dart';

/// One family tier's linked discount — a real discount value, exactly one of
/// [percentageOff] / [dollarOff] set (mirrors a regular discount). `dollarOff`
/// is minor units (cents). Sent on plan create/update and resolved back on read.
@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class LinkedDiscountValue extends Equatable {
  final double? percentageOff;
  final int? dollarOff;

  const LinkedDiscountValue({this.percentageOff, this.dollarOff});

  factory LinkedDiscountValue.fromJson(Map<String, dynamic> json) =>
      _$LinkedDiscountValueFromJson(json);

  Map<String, dynamic> toJson() => _$LinkedDiscountValueToJson(this);

  @override
  List<Object?> get props => [percentageOff, dollarOff];
}
