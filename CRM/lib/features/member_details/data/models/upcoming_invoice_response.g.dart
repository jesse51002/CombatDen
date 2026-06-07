// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upcoming_invoice_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpcomingInvoiceResponse _$UpcomingInvoiceResponseFromJson(
  Map<String, dynamic> json,
) => UpcomingInvoiceResponse(
  amountDue: (json['amount_due'] as num).toInt(),
  subtotal: (json['subtotal'] as num).toInt(),
  total: (json['total'] as num).toInt(),
  currency: json['currency'] as String,
  lines:
      (json['lines'] as List<dynamic>?)
          ?.map((e) => UpcomingInvoiceLine.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

UpcomingInvoiceLine _$UpcomingInvoiceLineFromJson(Map<String, dynamic> json) =>
    UpcomingInvoiceLine(
      stripeSubscriptionItemId: json['stripe_subscription_item_id'] as String,
      stripePriceId: json['stripe_price_id'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      amount: (json['amount'] as num).toInt(),
    );
