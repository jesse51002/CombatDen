// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaymentRecord _$PaymentRecordFromJson(Map<String, dynamic> json) =>
    PaymentRecord(
      transactionId: json['transaction_id'] as String,
      itemType: json['item_type'] as String?,
      amountPaid: (json['amount_paid'] as num).toDouble(),
      time: DateTime.parse(json['time'] as String),
    );
