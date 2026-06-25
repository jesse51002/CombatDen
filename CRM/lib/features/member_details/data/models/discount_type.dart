import 'package:json_annotation/json_annotation.dart';

/// Source type of a gym-level discount.
@JsonEnum(valueField: 'value')
enum DiscountType {
  preset('preset', 'Preset'),
  custom('custom', 'Custom'),
  unknown('unknown', 'Unknown');

  const DiscountType(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static DiscountType fromJson(String value) {
    return DiscountType.values.firstWhere(
      (v) => v.value == value,
      orElse: () => DiscountType.unknown,
    );
  }

  String toJson() => value;
}
