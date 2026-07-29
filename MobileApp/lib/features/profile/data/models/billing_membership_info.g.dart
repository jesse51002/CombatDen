// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'billing_membership_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BillingMembershipInfo _$BillingMembershipInfoFromJson(
  Map<String, dynamic> json,
) => BillingMembershipInfo(
  planId: json['plan_id'] as String,
  planName: json['plan_name'] as String,
  status: $enumDecode(
    _$CrmMemberStatusEnumMap,
    json['status'],
    unknownValue: CrmMemberStatus.unknown,
  ),
  itemId: json['item_id'] as String,
  paidByMemberId: json['paid_by_member_id'] as String,
  baseCost: (json['base_cost'] as num).toInt(),
  durationAmount: (json['duration_amount'] as num).toInt(),
  durationUnit: json['duration_unit'] as String,
  totalPrice: (json['total_price'] as num).toInt(),
  startDate: json['start_date'] as String,
  planType: $enumDecodeNullable(
    _$PlanTypeEnumMap,
    json['plan_type'],
    unknownValue: PlanType.unknown,
  ),
  currentActivePrice: (json['current_active_price'] as num?)?.toInt(),
  onOutdatedPrice: json['on_outdated_price'] as bool? ?? false,
  lastPaidDate: json['last_paid_date'] as String?,
  nextDueDate: json['next_due_date'] as String?,
  endDate: json['end_date'] as String?,
  cancelDate: json['cancel_date'] as String?,
  freezeStartDate: json['freeze_start_date'] as String?,
  freezeEndDate: json['freeze_end_date'] as String?,
  classCount: (json['class_count'] as num?)?.toInt(),
  classesUsed: (json['classes_used'] as num?)?.toInt() ?? 0,
  classesRemaining: (json['classes_remaining'] as num?)?.toInt(),
  discounts:
      (json['discounts'] as List<dynamic>?)
          ?.map(
            (e) => MemberMembershipAppliedDiscount.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList() ??
      [],
);

const _$CrmMemberStatusEnumMap = {
  CrmMemberStatus.active: 'active',
  CrmMemberStatus.trial: 'trial',
  CrmMemberStatus.frozen: 'frozen',
  CrmMemberStatus.cancelled: 'cancelled',
  CrmMemberStatus.ended: 'ended',
  CrmMemberStatus.overdue: 'overdue',
  CrmMemberStatus.unknown: 'unknown',
};

const _$PlanTypeEnumMap = {
  PlanType.trial: 'trial',
  PlanType.oneTime: 'one_time',
  PlanType.recurring: 'recurring',
  PlanType.unknown: 'unknown',
};
