import 'package:json_annotation/json_annotation.dart';

/// Kind of a Stripe-backed charge record.
@JsonEnum(valueField: 'value')
enum ChargeKind {
  payment('payment', 'Payment'),
  refund('refund', 'Refund'),
  unknown('unknown', 'Unknown');

  const ChargeKind(this.value, this.displayLabel);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Human-readable label for the UI.
  final String displayLabel;

  /// Parses a JSON string into a [ChargeKind].
  ///
  /// Falls back to [unknown] for unrecognised values so
  /// the app stays resilient when the backend adds new
  /// charge kinds.
  static ChargeKind fromJson(String value) {
    return ChargeKind.values.firstWhere(
      (v) => v.value == value,
      orElse: () => ChargeKind.unknown,
    );
  }

  /// Converts to a JSON string.
  String toJson() => value;
}
