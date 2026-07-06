import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rank_member_row.g.dart';

/// One member currently on a given main rank, from
/// `GET /api/v1/ranks/{rank_id}/members`.
///
/// [classesSince] is attendance since the member's last rank change;
/// [stepDenominator] is the classes needed to reach the next leaf.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankMemberRow extends Equatable {
  final String memberId;
  final String name;
  final String? avatarUrl;
  final int? currentSubIndex;
  final String? subLabel;
  final int classesSince;
  final int? stepDenominator;

  const RankMemberRow({
    required this.memberId,
    required this.name,
    this.avatarUrl,
    this.currentSubIndex,
    this.subLabel,
    required this.classesSince,
    this.stepDenominator,
  });

  factory RankMemberRow.fromJson(Map<String, dynamic> json) =>
      _$RankMemberRowFromJson(json);

  @override
  List<Object?> get props => [
        memberId,
        name,
        avatarUrl,
        currentSubIndex,
        subLabel,
        classesSince,
        stepDenominator,
      ];
}
