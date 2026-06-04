import 'package:json_annotation/json_annotation.dart';

/// Processing status of a Stripe-backed charge record.
@JsonEnum(valueField: 'value')
enum ChargeStatus {
  pending('pending', 'Pending'),
  succeeded('succeeded', 'Succeeded'),
  failed('failed', 'Failed'),
  unknown('unknown', 'Unknown');

  const ChargeStatus(this.value, this.displayLabel);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Human-readable label for the UI.
  final String displayLabel;

  /// Parses a JSON string into a [ChargeStatus].
  ///
  /// Falls back to [unknown] for unrecognised values so
  /// the app stays resilient when the backend adds new
  /// charge statuses.
  static ChargeStatus fromJson(String value) {
    return ChargeStatus.values.firstWhere(
      (v) => v.value == value,
      orElse: () => ChargeStatus.unknown,
    );
  }

  /// Converts to a JSON string.
  String toJson() => value;
}
