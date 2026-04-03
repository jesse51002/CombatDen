import 'package:json_annotation/json_annotation.dart';

/// Available views for the members list screen.
@JsonEnum(valueField: 'value')
enum MembersListView {
  all('all', 'All'),
  trial('trial', 'Trial'),
  frozen('frozen', 'Frozen'),
  overdue('overdue', 'Overdue');

  const MembersListView(this.value, this.displayLabel);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Human-readable label for the UI.
  final String displayLabel;

  /// Parses a JSON string into a [MembersListView].
  /// Falls back to [all] for unrecognised values.
  static MembersListView fromJson(String value) {
    return MembersListView.values.firstWhere(
      (v) => v.value == value,
      orElse: () => MembersListView.all,
    );
  }

  /// Converts to a JSON string.
  String toJson() => value;
}
