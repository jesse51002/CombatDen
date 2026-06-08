// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payments_invoice_preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PreviewInvoiceLine _$PreviewInvoiceLineFromJson(Map<String, dynamic> json) =>
    PreviewInvoiceLine(
      amount: (json['amount'] as num).toInt(),
      discountedAmount: (json['discounted_amount'] as num).toInt(),
      description: json['description'] as String?,
      stripePriceId: json['stripe_price_id'] as String?,
      quantity: (json['quantity'] as num?)?.toInt(),
      stripeSubscriptionItemId: json['stripe_subscription_item_id'] as String?,
      isProration: json['is_proration'] as bool? ?? false,
    );

PreviewInvoice _$PreviewInvoiceFromJson(Map<String, dynamic> json) =>
    PreviewInvoice(
      amountDue: (json['amount_due'] as num).toInt(),
      subtotal: (json['subtotal'] as num).toInt(),
      total: (json['total'] as num).toInt(),
      currency: json['currency'] as String,
      lines:
          (json['lines'] as List<dynamic>?)
              ?.map(
                (e) => PreviewInvoiceLine.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      nextPaymentDate: (json['next_payment_date'] as num?)?.toInt(),
    );

DueNowVsRecurringPreview _$DueNowVsRecurringPreviewFromJson(
  Map<String, dynamic> json,
) => DueNowVsRecurringPreview(
  dueNow: json['due_now'] == null
      ? null
      : PreviewInvoice.fromJson(json['due_now'] as Map<String, dynamic>),
  recurring: json['recurring'] == null
      ? null
      : PreviewInvoice.fromJson(json['recurring'] as Map<String, dynamic>),
);
