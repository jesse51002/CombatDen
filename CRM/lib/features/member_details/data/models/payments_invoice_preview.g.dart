// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payments_invoice_preview.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaymentsInvoicePreviewLineItem _$PaymentsInvoicePreviewLineItemFromJson(
  Map<String, dynamic> json,
) => PaymentsInvoicePreviewLineItem(
  amount: (json['amount'] as num).toInt(),
  description: json['description'] as String?,
  stripePriceId: json['stripe_price_id'] as String?,
  quantity: (json['quantity'] as num?)?.toInt(),
);

PaymentsInvoicePreviewResponse _$PaymentsInvoicePreviewResponseFromJson(
  Map<String, dynamic> json,
) => PaymentsInvoicePreviewResponse(
  amountDue: (json['amount_due'] as num).toInt(),
  subtotal: (json['subtotal'] as num).toInt(),
  total: (json['total'] as num).toInt(),
  currency: json['currency'] as String,
  lines:
      (json['lines'] as List<dynamic>?)
          ?.map(
            (e) => PaymentsInvoicePreviewLineItem.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList() ??
      [],
);

DueNowVsRecurringPreview _$DueNowVsRecurringPreviewFromJson(
  Map<String, dynamic> json,
) => DueNowVsRecurringPreview(
  dueNow: json['due_now'] == null
      ? null
      : PaymentsInvoicePreviewResponse.fromJson(
          json['due_now'] as Map<String, dynamic>,
        ),
  recurring: json['recurring'] == null
      ? null
      : PaymentsInvoicePreviewResponse.fromJson(
          json['recurring'] as Map<String, dynamic>,
        ),
);
