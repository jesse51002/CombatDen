import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rank_ready_row.g.dart';

/// One member on the ready-to-promote board, from
/// `GET /api/v1/ranks/ready-to-promote`.
///
/// [classesSince] is attendance since the member's last rank change
/// (the progress anchor); [stepDenominator] is the classes needed to
/// reach the next leaf (an even split of the main rank's
/// `classes_to_next_major` across sub-positions, else the full major
/// threshold).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankReadyRow extends Equatable {
  final String memberId;
  final String name;
  final String? avatarUrl;
  final String mainRankId;
  final String mainName;
  final int? currentSubIndex;
  final String? imageUrl;
  final int classesSince;
  final int? stepDenominator;

  const RankReadyRow({
    required this.memberId,
    required this.name,
    this.avatarUrl,
    required this.mainRankId,
    required this.mainName,
    this.currentSubIndex,
    this.imageUrl,
    required this.classesSince,
    this.stepDenominator,
  });

  factory RankReadyRow.fromJson(Map<String, dynamic> json) =>
      _$RankReadyRowFromJson(json);

  @override
  List<Object?> get props => [
        memberId,
        name,
        avatarUrl,
        mainRankId,
        mainName,
        currentSubIndex,
        imageUrl,
        classesSince,
        stepDenominator,
      ];
}
