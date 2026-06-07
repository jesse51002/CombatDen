import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'retention.g.dart';

/// Member retention and engagement statistics.
///
/// Mirrors the merged `BillingRetention` schema.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class Retention extends Equatable {
  final DateTime? lastClass;
  final int classStreakWeeks;
  final int pointsBalance;
  final int videosWatched;

  const Retention({
    this.lastClass,
    required this.classStreakWeeks,
    required this.pointsBalance,
    required this.videosWatched,
  });

  factory Retention.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$RetentionFromJson(json);

  /// Days since the member's last class, or null if
  /// unknown.
  int? get daysSinceLastClass {
    if (lastClass == null) return null;
    return DateTime.now().difference(lastClass!).inDays;
  }

  @override
  List<Object?> get props => [
        lastClass,
        classStreakWeeks,
        pointsBalance,
        videosWatched,
      ];
}
