import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';

part 'discount_response.g.dart';

/// A gym-level, regular-only discount preset.
///
/// Mirrors `DiscountResponse` from `GET /api/v1/discounts/`.
/// The discount's value spec (amount, mode, lifetime) lives
/// entirely in [value] — there are no flat top-level
/// amount/mode/lifetime fields.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
  explicitToJson: true,
)
class DiscountResponse extends Equatable {
  final String discountId;
  final String gymId;
  final String discountName;
  @JsonKey(fromJson: DiscountType.fromJson)
  final DiscountType discountType;
  final String valueId;
  final DiscountValue value;
  @JsonKey(defaultValue: false)
  final bool isDeleted;
  final DateTime createdAt;

  const DiscountResponse({
    required this.discountId,
    required this.gymId,
    required this.discountName,
    required this.discountType,
    required this.valueId,
    required this.value,
    this.isDeleted = false,
    required this.createdAt,
  });

  factory DiscountResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$DiscountResponseFromJson(json);

  /// Human-readable value — "20% off", "$10 off", else the
  /// preset name.
  String get displayLabel {
    if (value.percentageOff != null) {
      return '${value.percentageOff!.toStringAsFixed(0)}% off';
    }
    if (value.dollarOff != null) {
      final dollars = (value.dollarOff! / 100).toStringAsFixed(0);
      return '\$$dollars off';
    }
    return discountName;
  }

  @override
  List<Object?> get props => [
        discountId,
        gymId,
        discountName,
        discountType,
        valueId,
        value,
        isDeleted,
        createdAt,
      ];
}
