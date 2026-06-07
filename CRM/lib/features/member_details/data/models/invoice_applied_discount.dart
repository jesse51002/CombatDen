import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'invoice_applied_discount.g.dart';

/// A discount that was applied to a past invoice (a
/// payment-history line).
///
/// Sourced from the backend `BillingDiscountInfo`, itself read from
/// `member_invoice_applied_discounts` — the per-invoice audit the
/// `invoice.paid` webhook captures from Stripe. It is deliberately
/// **coupon-only**: the Stripe coupon id plus the dollars it took off
/// this invoice, NOT linked back to a CRM discount. (Currently-applied
/// membership discounts use the richer entitlement snapshot
/// `DiscountInfo` instead — distinct model, distinct purpose.)
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class InvoiceAppliedDiscount extends Equatable {
  final String stripeCouponId;

  /// Dollars taken off this invoice (minor units, >= 0).
  final int amountOff;

  const InvoiceAppliedDiscount({
    required this.stripeCouponId,
    required this.amountOff,
  });

  factory InvoiceAppliedDiscount.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$InvoiceAppliedDiscountFromJson(json);

  @override
  List<Object?> get props => [stripeCouponId, amountOff];
}
