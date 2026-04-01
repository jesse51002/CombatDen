import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'payment_record.g.dart';

/// A single payment transaction.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PaymentRecord extends Equatable {
  final String transactionId;
  final String? itemType;
  final double amountPaid;
  final DateTime time;

  const PaymentRecord({
    required this.transactionId,
    this.itemType,
    required this.amountPaid,
    required this.time,
  });

  factory PaymentRecord.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PaymentRecordFromJson(json);

  @override
  List<Object?> get props => [
        transactionId,
        itemType,
        amountPaid,
        time,
      ];
}
