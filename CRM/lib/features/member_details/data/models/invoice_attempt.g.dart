// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_attempt.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InvoiceAttempt _$InvoiceAttemptFromJson(Map<String, dynamic> json) =>
    InvoiceAttempt(
      chargeId: json['charge_id'] as String,
      kind: ChargeKind.fromJson(json['kind'] as String),
      status: ChargeStatus.fromJson(json['status'] as String),
      amount: (json['amount'] as num).toInt(),
      paymentMethodType: json['payment_method_type'] as String?,
      cardLastFour: json['card_last_four'] as String?,
      chargeTime: DateTime.parse(json['charge_time'] as String),
    );
