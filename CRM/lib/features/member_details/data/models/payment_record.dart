import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/charge_kind.dart';
import 'package:crm/features/member_details/data/models/charge_status.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/line_item_record.dart';

part 'payment_record.g.dart';

/// A single charge (payment or refund) against an invoice.
///
/// [amount] is a signed integer in the smallest unit of
/// [currency] (e.g. cents). Payments are >= 0, refunds
/// are <= 0.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PaymentRecord extends Equatable {
  final String chargeId;
  final String invoiceId;
  @JsonKey(fromJson: ChargeKind.fromJson)
  final ChargeKind kind;
  @JsonKey(fromJson: ChargeStatus.fromJson)
  final ChargeStatus status;
  final int amount;
  final String currency;
  final String? paymentMethodType;
  final DateTime chargeTime;
  final String? refundsChargeId;

  /// Total refunded against this charge (minor units, >= 0).
  /// Refunds are folded into the original charge rather than
  /// shown as separate rows.
  @JsonKey(defaultValue: 0)
  final int refundedAmount;

  /// The account that was charged (the payer).
  final String paidByMemberId;
  @JsonKey(defaultValue: '')
  final String paidByFirstName;
  @JsonKey(defaultValue: '')
  final String paidByLastName;
  final String? paidByPhotoUrl;

  @JsonKey(defaultValue: [])
  final List<LineItemRecord> lineItems;
  @JsonKey(defaultValue: [])
  final List<DiscountInfo> appliedDiscounts;

  const PaymentRecord({
    required this.chargeId,
    required this.invoiceId,
    required this.kind,
    required this.status,
    required this.amount,
    required this.currency,
    this.paymentMethodType,
    required this.chargeTime,
    this.refundsChargeId,
    this.refundedAmount = 0,
    required this.paidByMemberId,
    this.paidByFirstName = '',
    this.paidByLastName = '',
    this.paidByPhotoUrl,
    this.lineItems = const [],
    this.appliedDiscounts = const [],
  });

  /// The payer's display name.
  String get paidByName =>
      '$paidByFirstName $paidByLastName'.trim();

  /// Amount left after refunds (minor units).
  int get netAmount => amount - refundedAmount;

  /// True when some — but not all — of the charge was refunded.
  bool get isPartiallyRefunded =>
      refundedAmount > 0 && refundedAmount < amount;

  /// True when the whole charge was refunded.
  bool get isFullyRefunded =>
      refundedAmount > 0 && refundedAmount >= amount;

  factory PaymentRecord.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PaymentRecordFromJson(json);

  @override
  List<Object?> get props => [
        chargeId,
        invoiceId,
        kind,
        status,
        amount,
        currency,
        paymentMethodType,
        chargeTime,
        refundsChargeId,
        refundedAmount,
        paidByMemberId,
        paidByFirstName,
        paidByLastName,
        paidByPhotoUrl,
        lineItems,
        appliedDiscounts,
      ];
}
