// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaymentRecord _$PaymentRecordFromJson(Map<String, dynamic> json) =>
    PaymentRecord(
      chargeId: json['charge_id'] as String,
      invoiceId: json['invoice_id'] as String,
      kind: ChargeKind.fromJson(json['kind'] as String),
      status: ChargeStatus.fromJson(json['status'] as String),
      amount: (json['amount'] as num).toInt(),
      currency: json['currency'] as String,
      paymentMethodType: json['payment_method_type'] as String?,
      chargeTime: DateTime.parse(json['charge_time'] as String),
      refundsChargeId: json['refunds_charge_id'] as String?,
      refundedAmount: (json['refunded_amount'] as num?)?.toInt() ?? 0,
      paidByMemberId: json['paid_by_member_id'] as String,
      paidByFirstName: json['paid_by_first_name'] as String? ?? '',
      paidByLastName: json['paid_by_last_name'] as String? ?? '',
      paidByPhotoUrl: json['paid_by_photo_url'] as String?,
      paidFor:
          (json['paid_for'] as List<dynamic>?)
              ?.map((e) => PaidForMember.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      lineItems:
          (json['line_items'] as List<dynamic>?)
              ?.map((e) => LineItemRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      appliedDiscounts:
          (json['applied_discounts'] as List<dynamic>?)
              ?.map(
                (e) =>
                    InvoiceAppliedDiscount.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      attempts:
          (json['attempts'] as List<dynamic>?)
              ?.map((e) => InvoiceAttempt.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
