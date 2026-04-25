import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/stripe_coupon_duration.dart';

part 'discount_response.g.dart';

/// A gym-level discount definition.
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
  final double? percentageOff;
  final int? dollarOff;
  final String? membershipPlanId;
  final int? linkedDiscountNum;
  @JsonKey(fromJson: StripeCouponDuration.fromJson)
  final StripeCouponDuration duration;
  final int? durationInMonths;
  final String? stripeCouponId;
  final DateTime createdAt;

  const DiscountResponse({
    required this.discountId,
    required this.gymId,
    required this.discountName,
    required this.discountType,
    this.percentageOff,
    this.dollarOff,
    this.membershipPlanId,
    this.linkedDiscountNum,
    required this.duration,
    this.durationInMonths,
    this.stripeCouponId,
    required this.createdAt,
  });

  factory DiscountResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$DiscountResponseFromJson(json);

  /// Human-readable summary — "20% off", "$10 off", etc.
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
        percentageOff,
        dollarOff,
        membershipPlanId,
        linkedDiscountNum,
        duration,
        durationInMonths,
        stripeCouponId,
        createdAt,
      ];
}
