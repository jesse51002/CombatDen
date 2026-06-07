import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/charge_kind.dart';
import 'package:crm/features/member_details/data/models/charge_status.dart';

part 'invoice_attempt.g.dart';

/// One charge against an invoice — a retry, the success, or a refund.
///
/// The invoice popup lists every attempt so staff see the full payment
/// history of a single invoice (e.g. a failed card, then a successful one),
/// each with its method and, for a card, the last four digits. [amount] is a
/// signed integer in minor units (payments >= 0, refunds <= 0).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class InvoiceAttempt extends Equatable {
  final String chargeId;
  @JsonKey(fromJson: ChargeKind.fromJson)
  final ChargeKind kind;
  @JsonKey(fromJson: ChargeStatus.fromJson)
  final ChargeStatus status;
  final int amount;
  final String? paymentMethodType;

  /// Last four digits of the card, when the charge was on a card.
  final String? cardLastFour;
  final DateTime chargeTime;

  const InvoiceAttempt({
    required this.chargeId,
    required this.kind,
    required this.status,
    required this.amount,
    this.paymentMethodType,
    this.cardLastFour,
    required this.chargeTime,
  });

  factory InvoiceAttempt.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$InvoiceAttemptFromJson(json);

  @override
  List<Object?> get props => [
        chargeId,
        kind,
        status,
        amount,
        paymentMethodType,
        cardLastFour,
        chargeTime,
      ];
}
