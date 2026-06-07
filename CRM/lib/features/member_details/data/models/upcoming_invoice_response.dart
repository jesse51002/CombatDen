import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'upcoming_invoice_response.g.dart';

/// Preview of the next invoice for an existing subscription,
/// from `GET /api/v1/members/{member_id}/upcoming-invoice`.
///
/// Mirrors the backend `UpcomingInvoiceResponse` schema. The
/// endpoint returns `null` when the account has no recurring
/// subscription, so callers treat absence as "no next invoice".
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class UpcomingInvoiceResponse extends Equatable {
  final int amountDue;
  final int subtotal;
  final int total;
  final String currency;
  @JsonKey(defaultValue: [])
  final List<UpcomingInvoiceLine> lines;

  const UpcomingInvoiceResponse({
    required this.amountDue,
    required this.subtotal,
    required this.total,
    required this.currency,
    this.lines = const [],
  });

  factory UpcomingInvoiceResponse.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$UpcomingInvoiceResponseFromJson(json);

  @override
  List<Object?> get props => [
        amountDue,
        subtotal,
        total,
        currency,
        lines,
      ];
}

/// A single post-discount line on an upcoming subscription
/// invoice.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class UpcomingInvoiceLine extends Equatable {
  final String stripeSubscriptionItemId;
  final String? stripePriceId;
  final int quantity;

  /// Post-discount line total (minor units).
  final int amount;

  const UpcomingInvoiceLine({
    required this.stripeSubscriptionItemId,
    this.stripePriceId,
    required this.quantity,
    required this.amount,
  });

  factory UpcomingInvoiceLine.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$UpcomingInvoiceLineFromJson(json);

  @override
  List<Object?> get props => [
        stripeSubscriptionItemId,
        stripePriceId,
        quantity,
        amount,
      ];
}
