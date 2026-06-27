// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MembershipInfo _$MembershipInfoFromJson(Map<String, dynamic> json) =>
    MembershipInfo(
      planId: json['plan_id'] as String,
      planName: json['plan_name'] as String,
      planType: json['plan_type'] as String?,
      status: MembershipStatus.fromJson(json['status'] as String),
      itemId: json['item_id'] as String,
      paidByMemberId: json['paid_by_member_id'] as String,
      baseCost: (json['base_cost'] as num).toInt(),
      currentActivePrice: (json['current_active_price'] as num?)?.toInt(),
      onOutdatedPrice: json['on_outdated_price'] as bool? ?? false,
      durationAmount: (json['duration_amount'] as num).toInt(),
      durationUnit: json['duration_unit'] as String,
      totalPrice: (json['total_price'] as num).toInt(),
      lastPaidDate: json['last_paid_date'] == null
          ? null
          : DateTime.parse(json['last_paid_date'] as String),
      nextDueDate: json['next_due_date'] == null
          ? null
          : DateTime.parse(json['next_due_date'] as String),
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
      cancelDate: json['cancel_date'] == null
          ? null
          : DateTime.parse(json['cancel_date'] as String),
      freezeStartDate: json['freeze_start_date'] == null
          ? null
          : DateTime.parse(json['freeze_start_date'] as String),
      freezeEndDate: json['freeze_end_date'] == null
          ? null
          : DateTime.parse(json['freeze_end_date'] as String),
      classCount: (json['class_count'] as num?)?.toInt(),
      classesUsed: (json['classes_used'] as num?)?.toInt() ?? 0,
      classesRemaining: (json['classes_remaining'] as num?)?.toInt(),
      discounts:
          (json['discounts'] as List<dynamic>?)
              ?.map((e) => DiscountInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
