import 'package:json_annotation/json_annotation.dart';

/// Membership plan category.
@JsonEnum(valueField: 'value')
enum PlanType {
  trial('trial', 'Trial'),
  oneTime('one_time', 'One-time'),
  recurring('recurring', 'Recurring'),
  unknown('unknown', 'Unknown');

  const PlanType(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static PlanType fromJson(String value) {
    return PlanType.values.firstWhere(
      (v) => v.value == value,
      orElse: () => PlanType.unknown,
    );
  }

  String toJson() => value;
}
