import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/memberships/data/models/main_rank.dart';

part 'rank_member_response.g.dart';

/// Result of a manual member rank change (promote / set) — mirrors
/// the backend `RankMemberResponse`.
///
/// [newRank] is the member's MAIN rank after the change (`null` when
/// unassigned). [newSubIndex] is the leaf position within it (`null`
/// when the rank has no sub-ranks, or when unassigned);
/// [newSubLabel] / [newDisplayName] are the derived labels.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankMemberResponse extends Equatable {
  final String memberId;
  final MainRank? newRank;
  final int? newSubIndex;
  final String? newSubLabel;
  final String? newDisplayName;

  const RankMemberResponse({
    required this.memberId,
    this.newRank,
    this.newSubIndex,
    this.newSubLabel,
    this.newDisplayName,
  });

  factory RankMemberResponse.fromJson(Map<String, dynamic> json) =>
      _$RankMemberResponseFromJson(json);

  @override
  List<Object?> get props => [
        memberId,
        newRank,
        newSubIndex,
        newSubLabel,
        newDisplayName,
      ];
}
