import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'membership_plan_price_with_count.g.dart';

/// A membership plan price version plus how many members are still on
/// it. Returned by `GET /api/v1/membership_plans/{plan_id}/prices`.
///
/// `price` is in minor currency units (cents). `memberCount` is the
/// number of members still pinned to this version — the edit form shows
/// the active price plus any older version with `memberCount > 0` so the
/// gym can migrate them onto the current price.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembershipPlanPriceWithCount extends Equatable {
  final String priceId;
  final String planId;
  final String gymId;
  final String stripePriceId;
  final int price;
  final bool isActive;
  final DateTime createdAt;
  final int memberCount;

  const MembershipPlanPriceWithCount({
    required this.priceId,
    required this.planId,
    required this.gymId,
    required this.stripePriceId,
    required this.price,
    required this.isActive,
    required this.createdAt,
    required this.memberCount,
  });

  factory MembershipPlanPriceWithCount.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MembershipPlanPriceWithCountFromJson(json);

  @override
  List<Object?> get props => [
        priceId,
        planId,
        gymId,
        stripePriceId,
        price,
        isActive,
        createdAt,
        memberCount,
      ];
}
