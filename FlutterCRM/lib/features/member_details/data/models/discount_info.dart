import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'discount_info.g.dart';

/// An active discount applied to a membership.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class DiscountInfo extends Equatable {
  final String discountId;
  final String discountName;
  final double? percentageOff;
  final double? dollarOff;
  final DateTime? startDate;
  final DateTime? endDate;

  const DiscountInfo({
    required this.discountId,
    required this.discountName,
    this.percentageOff,
    this.dollarOff,
    this.startDate,
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
      return '\$${dollarOff!.toStringAsFixed(0)} off';
    }
    return '';
  }

  @override
  List<Object?> get props => [
        discountId,
        discountName,
        percentageOff,
        dollarOff,
        startDate,
        endDate,
      ];
}
