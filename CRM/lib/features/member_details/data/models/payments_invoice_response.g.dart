// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payments_invoice_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaymentsInvoiceResponse _$PaymentsInvoiceResponseFromJson(
  Map<String, dynamic> json,
) => PaymentsInvoiceResponse(
  stripeInvoiceId: json['stripe_invoice_id'] as String,
  stripeSubscriptionId: json['stripe_subscription_id'] as String?,
  amountDue: (json['amount_due'] as num).toInt(),
  amountPaid: (json['amount_paid'] as num).toInt(),
  amountRemaining: (json['amount_remaining'] as num).toInt(),
  currency: json['currency'] as String,
  status: json['status'] as String?,
  created: (json['created'] as num).toInt(),
  hostedInvoiceUrl: json['hosted_invoice_url'] as String?,
  invoicePdf: json['invoice_pdf'] as String?,
);
