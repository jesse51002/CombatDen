import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'payments_invoice_preview.g.dart';

/// A single line item from an invoice preview.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PaymentsInvoicePreviewLineItem extends Equatable {
  final int amount;
  final String? description;
  final String? stripePriceId;
  final int? quantity;

  const PaymentsInvoicePreviewLineItem({
    required this.amount,
    this.description,
    this.stripePriceId,
    this.quantity,
  });

  factory PaymentsInvoicePreviewLineItem.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PaymentsInvoicePreviewLineItemFromJson(json);

  @override
  List<Object?> get props => [
        amount,
        description,
        stripePriceId,
        quantity,
      ];
}

/// Preview of what an invoice would look like without
/// actually charging. Returned by every `*/preview`
/// backend endpoint.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PaymentsInvoicePreviewResponse extends Equatable {
  final int amountDue;
  final int subtotal;
  final int total;
  final String currency;
  @JsonKey(defaultValue: [])
  final List<PaymentsInvoicePreviewLineItem> lines;

  const PaymentsInvoicePreviewResponse({
    required this.amountDue,
    required this.subtotal,
    required this.total,
    required this.currency,
    this.lines = const [],
  });

  factory PaymentsInvoicePreviewResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PaymentsInvoicePreviewResponseFromJson(json);

  @override
  List<Object?> get props => [
        amountDue,
        subtotal,
        total,
        currency,
        lines,
      ];
}
