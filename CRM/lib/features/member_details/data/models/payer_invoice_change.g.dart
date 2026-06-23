// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payer_invoice_change.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PayerInvoiceChange _$PayerInvoiceChangeFromJson(Map<String, dynamic> json) =>
    PayerInvoiceChange(
      payerMemberId: json['payer_member_id'] as String,
      payerFirstName: json['payer_first_name'] as String,
      payerLastName: json['payer_last_name'] as String,
      preview: DueNowVsRecurringPreview.fromJson(
        json['preview'] as Map<String, dynamic>,
      ),
    );
