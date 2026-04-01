import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rank_retention.g.dart';

/// Rank progression and retention statistics.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class RankRetention extends Equatable {
  final int? currentRank;
  final String? rankName;
  final String? rankImageUrl;
  final int classesInRank;
  final int estimatedClassesForRank;
  final int? recommendPromoIn;
  final DateTime? lastClass;
  final int classStreakWeeks;
  final int pointsBalance;
  final int videosWatched;

  const RankRetention({
    this.currentRank,
    this.rankName,
    this.rankImageUrl,
    required this.classesInRank,
    required this.estimatedClassesForRank,
    this.recommendPromoIn,
    this.lastClass,
    required this.classStreakWeeks,
    required this.pointsBalance,
    required this.videosWatched,
  });

  factory RankRetention.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$RankRetentionFromJson(json);

  /// Days since the member's last class, or null if
  /// unknown.
  int? get daysSinceLastClass {
    if (lastClass == null) return null;
    return DateTime.now().difference(lastClass!).inDays;
  }

  @override
  List<Object?> get props => [
        currentRank,
        rankName,
        rankImageUrl,
        classesInRank,
        estimatedClassesForRank,
        recommendPromoIn,
        lastClass,
        classStreakWeeks,
        pointsBalance,
        videosWatched,
      ];
}
