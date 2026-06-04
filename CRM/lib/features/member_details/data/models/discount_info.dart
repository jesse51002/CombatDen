import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/core/utils/money.dart';

part 'discount_info.g.dart';

/// An active discount applied to a membership.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class DiscountInfo extends Equatable {
  final String discountId;
  final String discountName;
  final String discountType;
  final double? percentageOff;
  final int? dollarOff;
  final DateTime? endDate;

  const DiscountInfo({
    required this.discountId,
    required this.discountName,
    required this.discountType,
    this.percentageOff,
    this.dollarOff,
    this.endDate,
  });

  factory DiscountInfo.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$DiscountInfoFromJson(json);

  /// Returns a display string like "20% off" or "$10 off".
  String get discountLabel {
    if (percentageOff != null) {
      return '${percentageOff!.toStringAsFixed(0)}% off';
    }
    if (dollarOff != null) {
      return '${formatMinorUnits(dollarOff!)} off';
    }
    return '';
  }

  @override
  List<Object?> get props => [
        discountId,
        discountName,
        discountType,
        percentageOff,
        dollarOff,
        endDate,
      ];
}
