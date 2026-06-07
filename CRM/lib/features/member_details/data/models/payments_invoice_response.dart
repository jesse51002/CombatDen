import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'payments_invoice_response.g.dart';

/// A finalized Stripe invoice returned by
/// `GET /api/v1/members/{member_id}/invoices`.
///
/// Mirrors the merged `PaymentsInvoiceResponse` schema.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PaymentsInvoiceResponse extends Equatable {
  final String stripeInvoiceId;
  final String? stripeSubscriptionId;
  final int amountDue;
  final int amountPaid;
  final int amountRemaining;
  final String currency;
  final String? status;

  /// Unix timestamp (seconds) when the invoice was
  /// created on Stripe.
  final int created;
  final String? hostedInvoiceUrl;
  final String? invoicePdf;

  const PaymentsInvoiceResponse({
    required this.stripeInvoiceId,
    this.stripeSubscriptionId,
    required this.amountDue,
    required this.amountPaid,
    required this.amountRemaining,
    required this.currency,
    this.status,
    required this.created,
    this.hostedInvoiceUrl,
    this.invoicePdf,
  });

  factory PaymentsInvoiceResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PaymentsInvoiceResponseFromJson(json);

  /// [created] as a UTC [DateTime], converted from the
  /// Stripe epoch-seconds integer.
  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(
        created * 1000,
        isUtc: true,
      );

  @override
  List<Object?> get props => [
        stripeInvoiceId,
        stripeSubscriptionId,
        amountDue,
        amountPaid,
        amountRemaining,
        currency,
        status,
        created,
        hostedInvoiceUrl,
        invoicePdf,
      ];
}
