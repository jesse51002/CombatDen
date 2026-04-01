// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MembershipInfo _$MembershipInfoFromJson(Map<String, dynamic> json) =>
    MembershipInfo(
      planName: json['plan_name'] as String,
      planType: json['plan_type'] as String?,
      status: json['status'] as String,
      baseCost: (json['base_cost'] as num).toDouble(),
      billingCycle: json['billing_cycle'] as String,
      totalCost: (json['total_cost'] as num).toDouble(),
      costFormula: json['cost_formula'] as String,
      lastPaidDate: json['last_paid_date'] == null
          ? null
          : DateTime.parse(json['last_paid_date'] as String),
      nextDueDate: json['next_due_date'] == null
          ? null
          : DateTime.parse(json['next_due_date'] as String),
      startDate: DateTime.parse(json['start_date'] as String),
      linkedAccounts:
          (json['linked_accounts'] as List<dynamic>?)
              ?.map((e) => LinkedAccount.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      discounts:
          (json['discounts'] as List<dynamic>?)
              ?.map((e) => DiscountInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
