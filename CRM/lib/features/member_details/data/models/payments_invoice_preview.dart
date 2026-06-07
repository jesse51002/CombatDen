import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'payments_invoice_preview.g.dart';

/// A single line item from an invoice preview.
///
/// [amount] is Stripe's raw line amount (pre-discount on a subscription
/// preview); [discountedAmount] is the post-discount value. The line also
/// carries [stripeSubscriptionItemId] (null for one-off items) and
/// [isProration] so callers can filter to the steady-state recurring view.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PreviewInvoiceLine extends Equatable {
  final int amount;
  final int discountedAmount;
  final String? description;
  final String? stripePriceId;
  final int? quantity;
  final String? stripeSubscriptionItemId;
  @JsonKey(defaultValue: false)
  final bool isProration;

  const PreviewInvoiceLine({
    required this.amount,
    required this.discountedAmount,
    this.description,
    this.stripePriceId,
    this.quantity,
    this.stripeSubscriptionItemId,
    this.isProration = false,
  });

  factory PreviewInvoiceLine.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PreviewInvoiceLineFromJson(json);

  @override
  List<Object?> get props => [
        amount,
        discountedAmount,
        description,
        stripePriceId,
        quantity,
        stripeSubscriptionItemId,
        isProration,
      ];
}

/// Preview of what an invoice would look like without actually
/// charging — the one preview shape. Returned (directly, wrapped in
/// [DueNowVsRecurringPreview], or filtered to recurring lines for the
/// upcoming-invoice read) by every `*/preview` backend endpoint and the
/// upcoming-invoice endpoint.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class PreviewInvoice extends Equatable {
  final int amountDue;
  final int subtotal;
  final int total;
  final String currency;
  @JsonKey(defaultValue: [])
  final List<PreviewInvoiceLine> lines;

  const PreviewInvoice({
    required this.amountDue,
    required this.subtotal,
    required this.total,
    required this.currency,
    this.lines = const [],
  });

  factory PreviewInvoice.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$PreviewInvoiceFromJson(json);

  @override
  List<Object?> get props => [
        amountDue,
        subtotal,
        total,
        currency,
        lines,
      ];
}

/// A preview split into what is charged now vs. what recurs.
///
/// Both halves are ordinary invoice previews: [dueNow] is the
/// immediate charge (`null` when nothing is charged now), [recurring]
/// is the steady-state per-cycle invoice (`null` for a one-time
/// purchase, which never recurs). Returned by every `*/preview`
/// backend endpoint.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class DueNowVsRecurringPreview extends Equatable {
  final PreviewInvoice? dueNow;
  final PreviewInvoice? recurring;

  const DueNowVsRecurringPreview({
    this.dueNow,
    this.recurring,
  });

  factory DueNowVsRecurringPreview.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$DueNowVsRecurringPreviewFromJson(json);

  @override
  List<Object?> get props => [dueNow, recurring];
}
