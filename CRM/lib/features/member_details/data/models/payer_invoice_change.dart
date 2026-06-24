import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';

part 'payer_invoice_change.g.dart';

/// One payer's billing outcome from a (possibly batched) cancel. Mirrors
/// backend `PayerInvoiceChange`.
///
/// [affected] is a membership-level flag — true iff this payer funds at least
/// one membership being cancelled. When true, [preview] carries the standard
/// current → new comparison the `InvoicePreviewSection` renders; when false the
/// operation cancels nothing for them and [preview] is null (the UI shows no
/// billing change).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PayerInvoiceChange extends Equatable {
  final String payerMemberId;
  final String payerFirstName;
  final String payerLastName;
  final bool affected;
  final DueNowVsRecurringPreview? preview;

  const PayerInvoiceChange({
    required this.payerMemberId,
    required this.payerFirstName,
    required this.payerLastName,
    required this.affected,
    this.preview,
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
        affected,
        preview,
      ];
}
