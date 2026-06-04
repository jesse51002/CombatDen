import 'package:json_annotation/json_annotation.dart';

/// How long a Stripe coupon is applied for.
@JsonEnum(valueField: 'value')
enum StripeCouponDuration {
  once('once', 'Once'),
  repeating('repeating', 'Repeating'),
  forever('forever', 'Forever'),
  unknown('unknown', 'Unknown');

  const StripeCouponDuration(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static StripeCouponDuration fromJson(String value) {
    return StripeCouponDuration.values.firstWhere(
      (v) => v.value == value,
      orElse: () => StripeCouponDuration.unknown,
    );
  }

  String toJson() => value;
}
