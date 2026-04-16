import 'package:json_annotation/json_annotation.dart';

/// Type of an invoice line item.
@JsonEnum(valueField: 'value')
enum LineItemType {
  membership('membership', 'Membership'),
  custom('custom', 'Custom'),
  unknown('unknown', 'Unknown');

  const LineItemType(this.value, this.displayLabel);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Human-readable label for the UI.
  final String displayLabel;

  /// Parses a JSON string into a [LineItemType].
  ///
  /// Falls back to [unknown] for unrecognised values so
  /// the app stays resilient when the backend adds new
  /// line item types.
  static LineItemType fromJson(String value) {
    return LineItemType.values.firstWhere(
      (v) => v.value == value,
      orElse: () => LineItemType.unknown,
    );
  }

  /// Converts to a JSON string.
  String toJson() => value;
}
