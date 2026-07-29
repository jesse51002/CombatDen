import 'package:json_annotation/json_annotation.dart';

part 'member_membership_applied_discount.g.dart';

/// A discount's type. Mirrors `DiscountType` in
/// `Database/python_data/schema/gym_discount.py`. An unknown backend value
/// parses to [unknown] rather than crashing.
enum DiscountType {
  @JsonValue('preset')
  preset,
  @JsonValue('custom')
  custom,
  unknown,
}

/// A single applied-discount row pinned to one of a member's memberships.
///
/// Mirrors `MemberMembershipsAppliedDiscount` in
/// `FastApiBackend/src/memberships/memberships_schema.py` (reused by the
/// member-portal profile's membership cards).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberMembershipAppliedDiscount {
  final String appliedDiscountId;
  final String itemId;
  final String memberId;
  final String gymId;
  final String valueId;
  final String discountId;
  final String discountName;
  @JsonKey(unknownEnumValue: DiscountType.unknown)
  final DiscountType discountType;
  final double? percentageOff;
  final int? dollarOff;
  final String? endDate;
  final String? stripeCouponId;

  const MemberMembershipAppliedDiscount({
    required this.appliedDiscountId,
    required this.itemId,
    required this.memberId,
    required this.gymId,
    required this.valueId,
    required this.discountId,
    required this.discountName,
    required this.discountType,
    this.percentageOff,
    this.dollarOff,
    this.endDate,
    this.stripeCouponId,
  });

  factory MemberMembershipAppliedDiscount.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MemberMembershipAppliedDiscountFromJson(json);
}
