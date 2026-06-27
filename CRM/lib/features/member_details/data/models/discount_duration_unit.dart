import 'package:json_annotation/json_annotation.dart';

/// Unit of a discount preset's duration span.
///
/// Mirrors the backend `DiscountDurationUnit` enum (Database
/// package). Distinct from the plan-level [DurationUnit]
/// (week/month/year). `cycle` is one plan billing cycle (1
/// month for recurring plans) — the replacement for the
/// removed `once` mode. `day`/`week`/`month` are calendar
/// spans; neither = forever.
@JsonEnum(valueField: 'value')
enum DiscountDurationUnit {
  day('day', 'Day'),
  week('week', 'Week'),
  month('month', 'Month'),
  cycle('cycle', 'Cycle'),
  unknown('unknown', 'Unknown');

  const DiscountDurationUnit(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static DiscountDurationUnit fromJson(String value) {
    return DiscountDurationUnit.values.firstWhere(
      (v) => v.value == value,
      orElse: () => DiscountDurationUnit.unknown,
    );
  }

  String toJson() => value;
}
