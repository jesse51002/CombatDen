import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';

part 'payer_invoice_change.g.dart';

/// One payer's billing change from a (possibly batched) cancel — their
/// subscription's recurring bill current → new. Mirrors backend
/// `PayerInvoiceChange`.
///
/// A LIST of these is the cancel / remove-authorization cost preview: one entry
/// per affected payer. A single membership cancel yields a one-entry list; a
/// member's memberships funded by different payers can change several payers'
/// bills at once. [preview] is the standard current → new comparison the
/// `InvoicePreviewSection` renders.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PayerInvoiceChange extends Equatable {
  final String payerMemberId;
  final String payerFirstName;
  final String payerLastName;
  final DueNowVsRecurringPreview preview;

  const PayerInvoiceChange({
    required this.payerMemberId,
    required this.payerFirstName,
    required this.payerLastName,
    required this.preview,
  });

  factory PayerInvoiceChange.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PayerInvoiceChangeFromJson(json);

  String get payerFullName => '$payerFirstName $payerLastName';

  @override
  List<Object?> get props => [
        payerMemberId,
        payerFirstName,
        payerLastName,
        preview,
      ];
}
