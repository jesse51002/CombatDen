import 'package:json_annotation/json_annotation.dart';

part 'billing_rank.g.dart';

/// A member's current rank (belt leaf) for the profile rank block.
///
/// Mirrors `BillingRank` in
/// `FastApiBackend/src/members/schema/members_billing_schema.py`. Present only
/// when the member holds a rank and the gym has ranks enabled.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class BillingRank {
  final String rankId;
  final String name;
  final int? subIndex;
  final String? subLabel;
  final String? imageUrl;

  /// Headline threshold to the next MAJOR rank (gym-set).
  final int classesToNextMajor;

  /// Classes needed to reach the next LEAF (even split of
  /// [classesToNextMajor] across sub-positions, else the full major threshold).
  final int classesTillNextStep;

  /// Classes attended since the member's last promotion.
  @JsonKey(defaultValue: 0)
  final int classesSinceRank;

  const BillingRank({
    required this.rankId,
    required this.name,
    required this.classesToNextMajor,
    required this.classesTillNextStep,
    this.subIndex,
    this.subLabel,
    this.imageUrl,
    this.classesSinceRank = 0,
  });

  factory BillingRank.fromJson(Map<String, dynamic> json) =>
      _$BillingRankFromJson(json);
}
