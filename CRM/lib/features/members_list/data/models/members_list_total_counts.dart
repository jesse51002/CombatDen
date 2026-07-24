import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_list_total_counts.g.dart';

/// Aggregate member counts across the full dataset.
///
/// Always reflects totals regardless of active view
/// or filters.
///
/// These are independent tallies, not a partition: a member can be
/// counted under more than one heading (an overdue member is also
/// counted as active, and a dormant one is also counted as trial when
/// their pack is a trial).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembersListTotalCounts extends Equatable {
  final int active;
  final int trial;
  final int frozen;
  final int overdue;

  /// Holds only short packs and has gone quiet past the gym's
  /// dormancy window. Defaults to 0 so a client running against an
  /// older backend still parses.
  @JsonKey(defaultValue: 0)
  final int dormant;

  /// Signups that never finished: no membership of their own, and not
  /// the payer on anyone else's. The one tally that cannot overlap the
  /// others — every other heading requires a membership row. Defaults
  /// to 0 so a client running against an older backend still parses.
  @JsonKey(defaultValue: 0)
  final int incomplete;

  const MembersListTotalCounts({
    required this.active,
    required this.trial,
    required this.frozen,
    required this.overdue,
    this.dormant = 0,
    this.incomplete = 0,
  });

  factory MembersListTotalCounts.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$MembersListTotalCountsFromJson(json);

  @override
  List<Object?> get props => [
        active,
        trial,
        frozen,
        overdue,
        dormant,
        incomplete,
      ];
}
