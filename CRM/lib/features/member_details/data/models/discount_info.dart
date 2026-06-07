import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';

part 'discount_info.g.dart';

/// One applied-discount snapshot frozen onto a single
/// membership item.
///
/// Mirrors the backend `MemberMembershipsAppliedDiscount`:
/// every discount is item-scoped ([itemId]) and member-scoped
/// ([memberId]), identified by [appliedDiscountId] (the handle
/// the apply path removes by). The snapshot pins the membership
/// to an immutable value version ([valueId]) of its owning
/// discount ([discountId]); the name/value are resolved from
/// that version. Applying = add a row, removing = delete one by
/// [appliedDiscountId] — a snapshot is never edited.
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
  @JsonKey(fromJson: DiscountMode.fromJson)
  final DiscountMode discountMode;
  final DateTime? endDate;

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
    required this.discountMode,
    this.endDate,
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

  /// True when this snapshot is a family/linked discount.
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
        discountMode,
        endDate,
      ];
}
