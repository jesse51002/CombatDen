// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_row.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AllViewRow _$AllViewRowFromJson(Map<String, dynamic> json) => AllViewRow(
  memberId: json['member_id'] as String,
  name: json['name'] as String,
  avatarUrl: json['avatar_url'] as String?,
  email: json['email'] as String?,
  membershipStatus: MembershipStatus.fromJson(
    json['membership_status'] as String,
  ),
  membershipText: json['membership_text'] as String,
  daysSinceLastClass: (json['days_since_last_class'] as num?)?.toInt(),
);

TrialViewRow _$TrialViewRowFromJson(Map<String, dynamic> json) => TrialViewRow(
  memberId: json['member_id'] as String,
  name: json['name'] as String,
  avatarUrl: json['avatar_url'] as String?,
  daysRemaining: (json['days_remaining'] as num).toInt(),
  startDate: json['start_date'] as String,
  endDate: json['end_date'] as String,
);

FrozenViewRow _$FrozenViewRowFromJson(Map<String, dynamic> json) =>
    FrozenViewRow(
      memberId: json['member_id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      freezeStart: json['freeze_start'] as String,
      daysUntilUnfrozen: (json['days_until_unfrozen'] as num).toInt(),
      freezeEnd: json['freeze_end'] as String,
      price: json['price'] as String,
    );

OverdueViewRow _$OverdueViewRowFromJson(Map<String, dynamic> json) =>
    OverdueViewRow(
      memberId: json['member_id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      membershipText: json['membership_text'] as String,
      daysLate: (json['days_late'] as num).toInt(),
    );
