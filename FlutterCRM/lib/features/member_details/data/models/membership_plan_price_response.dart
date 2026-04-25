import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'membership_plan_price_response.g.dart';

/// A single Stripe price attached to a membership plan.
/// `price` is in minor currency units (e.g. cents).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembershipPlanPriceResponse extends Equatable {
  final String priceId;
  final String planId;
  final String gymId;
  final String stripePriceId;
  final int price;
  final bool isActive;
  final DateTime createdAt;

  const MembershipPlanPriceResponse({
    required this.priceId,
    required this.planId,
    required this.gymId,
    required this.stripePriceId,
    required this.price,
    required this.isActive,
    required this.createdAt,
  });

  factory MembershipPlanPriceResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MembershipPlanPriceResponseFromJson(json);

  @override
  List<Object?> get props => [
        priceId,
        planId,
        gymId,
        stripePriceId,
        price,
        isActive,
        createdAt,
      ];
}
