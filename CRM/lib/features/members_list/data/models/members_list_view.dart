import 'package:json_annotation/json_annotation.dart';

/// Available views for the members list screen.
///
/// [incomplete] is the staff follow-up queue for signups that never
/// finished: a member row holding no membership of their own who is also
/// not the payer on anyone else's. The rule lives in the backend
/// (`src/members/sql/crm_views/_member_incomplete.sql`).
@JsonEnum(valueField: 'value')
enum MembersListView {
  all('all', 'All'),
  trial('trial', 'Trial'),
  frozen('frozen', 'Frozen'),
  overdue('overdue', 'Overdue'),
  incomplete('incomplete', 'Incomplete');

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
