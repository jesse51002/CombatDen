import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';

part 'discount_info.g.dart';

/// One applied-discount row frozen onto a single
/// membership item.
///
/// Mirrors the backend `MemberMembershipsAppliedDiscount`:
/// every discount is item-scoped ([itemId]) and member-scoped
/// ([memberId]), identified by [appliedDiscountId] (the handle
/// the apply path removes by). The applied-discount row pins
/// the membership to an immutable value version ([valueId]) of
/// its owning discount ([discountId]); the name/value are
/// resolved from that version. Applying = add a row, removing
/// = delete one by [appliedDiscountId] — a row is never edited.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class DiscountInfo extends Equatable {
  final String appliedDiscountId;
  final String itemId;
  final String memberId;
  final String gymId;
  final String valueId;
  final String discountId;
  @JsonKey(fromJson: DiscountType.fromJson)
  final DiscountType discountType;
  final String discountName;
  final double? percentageOff;
  final int? dollarOff;
  final DateTime? endDate;
  // The coupon the sync resolved/wrote back (snake: stripe_coupon_id). Optional
  // and not consumed in the CRM yet, but tracked so the model matches the
  // backend MemberMembershipsAppliedDiscount contract exactly.
  final String? stripeCouponId;

  const DiscountInfo({
    required this.appliedDiscountId,
    required this.itemId,
    required this.memberId,
    required this.gymId,
    required this.valueId,
    required this.discountId,
    required this.discountType,
    required this.discountName,
    this.percentageOff,
    this.dollarOff,
    this.endDate,
    this.stripeCouponId,
  });

  factory DiscountInfo.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$DiscountInfoFromJson(json);

  /// Display string for the discount value — "20% off" or
  /// "$10 off".
  String get discountLabel {
    if (percentageOff != null) {
      return '${percentageOff!.toStringAsFixed(0)}% off';
    }
    if (dollarOff != null) {
      return '${formatMinorUnits(dollarOff!)} off';
    }
    return '';
  }

  /// True when this applied-discount row is a family/linked discount.
  bool get isLinked => discountType == DiscountType.linked;

  @override
  List<Object?> get props => [
        appliedDiscountId,
        itemId,
        memberId,
        gymId,
        valueId,
        discountId,
        discountType,
        discountName,
        percentageOff,
        dollarOff,
        endDate,
        stripeCouponId,
      ];
}
