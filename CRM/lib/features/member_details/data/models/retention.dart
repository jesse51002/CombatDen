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

  /// Days since the member's last class (calendar-day
  /// diff in local time, never negative — an evening
  /// class or an early check-in can put the raw
  /// timestamp ahead of now), or null if unknown.
  int? get daysSinceLastClass {
    if (lastClass == null) return null;
    final now = DateTime.now();
    final last = lastClass!.toLocal();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    return days < 0 ? 0 : days;
  }

  @override
  List<Object?> get props => [
        lastClass,
        classStreakWeeks,
        pointsBalance,
        videosWatched,
      ];
}
