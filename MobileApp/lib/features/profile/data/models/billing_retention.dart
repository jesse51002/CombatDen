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

  const BillingRetention({
    required this.classStreakWeeks,
    required this.pointsBalance,
    required this.videosWatched,
    this.lastClass,
  });

  factory BillingRetention.fromJson(Map<String, dynamic> json) =>
      _$BillingRetentionFromJson(json);
}
