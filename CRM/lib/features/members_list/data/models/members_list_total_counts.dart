import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'members_list_total_counts.g.dart';

/// Aggregate member counts across the full dataset.
///
/// Always reflects totals regardless of active view
/// or filters.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class MembersListTotalCounts extends Equatable {
  final int active;
  final int trial;
  final int frozen;
  final int overdue;

  const MembersListTotalCounts({
    required this.active,
    required this.trial,
    required this.frozen,
    required this.overdue,
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
      ];
}
