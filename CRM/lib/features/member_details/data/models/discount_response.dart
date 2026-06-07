import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';

part 'discount_response.g.dart';

/// A gym-level, regular-only discount preset.
///
/// Mirrors the reshaped `DiscountResponse` from
/// `GET /api/v1/discounts/`: presets are coupon-free intent
/// rows. Lifetime is [discountMode] (`once` / `ongoing`)
/// plus EITHER a duration span ([durationAmount] +
/// [durationUnit]) OR an explicit [endDate] — never both;
/// neither means forever. The old Stripe coupon /
/// linked-preset fields are gone (linked discounts are now
/// snapshot-only and have no preset entity).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class DiscountResponse extends Equatable {
  final String discountId;
  final String gymId;
  final String discountName;
  @JsonKey(fromJson: DiscountType.fromJson)
  final DiscountType discountType;
  final String valueId;
  final double? percentageOff;
  final int? dollarOff;
  @JsonKey(fromJson: DiscountMode.fromJson)
  final DiscountMode discountMode;
  final int? durationAmount;
  @JsonKey(fromJson: _durationUnitOrNull)
  final DiscountDurationUnit? durationUnit;
  final DateTime? endDate;
  @JsonKey(defaultValue: false)
  final bool isDeleted;
  final DateTime createdAt;

  const DiscountResponse({
    required this.discountId,
    required this.gymId,
    required this.discountName,
    required this.discountType,
    required this.valueId,
    this.percentageOff,
    this.dollarOff,
    required this.discountMode,
    this.durationAmount,
    this.durationUnit,
    this.endDate,
    this.isDeleted = false,
    required this.createdAt,
  });

  factory DiscountResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$DiscountResponseFromJson(json);

  static DiscountDurationUnit? _durationUnitOrNull(
    Object? value,
  ) =>
      value == null
          ? null
          : DiscountDurationUnit.fromJson(value as String);

  /// Human-readable value — "20% off", "$10 off", else the
  /// preset name.
  String get displayLabel {
    if (percentageOff != null) {
      return '${percentageOff!.toStringAsFixed(0)}% off';
    }
    if (dollarOff != null) {
      final dollars = (dollarOff! / 100)
          .toStringAsFixed(0);
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
        percentageOff,
        dollarOff,
        discountMode,
        durationAmount,
        durationUnit,
        endDate,
        isDeleted,
        createdAt,
      ];
}
