import 'package:json_annotation/json_annotation.dart';

/// How long an applied discount runs.
///
/// Mirrors the backend `DiscountMode` enum (Database
/// package). `once` lands on exactly one invoice; `ongoing`
/// runs until its resolved `end_date` (or forever when
/// neither a duration span nor an explicit end is set).
@JsonEnum(valueField: 'value')
enum DiscountMode {
  once('once', 'Once'),
  ongoing('ongoing', 'Ongoing'),
  unknown('unknown', 'Unknown');

  const DiscountMode(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static DiscountMode fromJson(String value) {
    return DiscountMode.values.firstWhere(
      (v) => v.value == value,
      orElse: () => DiscountMode.unknown,
    );
  }

  String toJson() => value;
}
