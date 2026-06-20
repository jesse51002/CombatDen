import 'package:json_annotation/json_annotation.dart';

/// How a membership's first (or repriced) recurring charge is handled
/// relative to the billing anchor — the date the next FULL cycle bills
/// (today the 1st of the next month, surfaced as `nextPaymentDate`).
///
/// Replaces the old `prorate` boolean: "unchecked" used to read like the
/// membership starts immediately / nothing happens, when it actually meant
/// no charge now with billing still beginning at the anchor.
///
/// - [prorateToAnchor] — charge the partial period from today through the
///   anchor immediately.
/// - [noCharge] — charge nothing now; the membership still starts and the
///   first full bill lands on the anchor.
@JsonEnum(valueField: 'value')
enum ProrationBehavior {
  prorateToAnchor('prorate_to_anchor', 'Prorate now'),
  noCharge('no_charge', 'No charge now'),
  unknown('unknown', 'Unknown');

  const ProrationBehavior(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static ProrationBehavior fromJson(String value) {
    return ProrationBehavior.values.firstWhere(
      (v) => v.value == value,
      orElse: () => ProrationBehavior.unknown,
    );
  }

  String toJson() => value;
}
