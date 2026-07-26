import 'package:json_annotation/json_annotation.dart';

part 'billing_retention.g.dart';

/// A member's retention / engagement stats — the topbar reads
/// [classStreakWeeks] and [pointsBalance] from here.
///
/// Mirrors `BillingRetention` in
/// `FastApiBackend/src/members/schema/members_billing_schema.py`. [lastClass]
/// is kept as the backend's raw ISO datetime string (display-only).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class BillingRetention {
  final String? lastClass;
  final int classStreakWeeks;
  final int pointsBalance;
  final int videosWatched;

  /// This week's attended weekdays, **Sunday-first** (0 = Sun … 6 = Sat),
  /// ascending, empty when none — the profile's week strip, served with the
  /// profile so the strip costs no second call.
  ///
  /// The WEEK is Monday-anchored (to match [classStreakWeeks]), so a Sunday is
  /// the LAST day of the streak week but is drawn in the strip's FIRST cell.
  /// That is deliberate — don't "fix" it.
  @JsonKey(defaultValue: <int>[])
  final List<int> currentWeekAttendedWeekdays;

  const BillingRetention({
    required this.classStreakWeeks,
    required this.pointsBalance,
    required this.videosWatched,
    this.lastClass,
    this.currentWeekAttendedWeekdays = const [],
  });

  factory BillingRetention.fromJson(Map<String, dynamic> json) =>
      _$BillingRetentionFromJson(json);
}
