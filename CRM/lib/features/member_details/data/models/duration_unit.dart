import 'package:json_annotation/json_annotation.dart';

/// Duration unit for a plan's billing cycle.
@JsonEnum(valueField: 'value')
enum DurationUnit {
  week('week', 'Week'),
  month('month', 'Month'),
  year('year', 'Year'),
  unknown('unknown', 'Unknown');

  const DurationUnit(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static DurationUnit fromJson(String value) {
    return DurationUnit.values.firstWhere(
      (v) => v.value == value,
      orElse: () => DurationUnit.unknown,
    );
  }

  String toJson() => value;
}
