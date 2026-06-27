import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';

/// Maps a single [PreviewInvoice] onto the shared, presentation-only
/// [InvoiceBreakdownData] — the plain (non-comparison) path shared by
/// the membership-start preview, the recurring half, and the
/// overdue/upcoming card.
///
/// Each line shows its undiscounted (list) price ([PreviewInvoiceLine.amount])
/// and, beneath it, the discount on that line (`discountedAmount − amount`,
/// negative). Stripe folds subscription coupons into `discount_amounts`
/// (not separate negative lines) and returns an already-post-discount
/// `subtotal`, so without this the lines would not reconcile with the
/// post-discount [PreviewInvoice.total]. [amountSuffix] tags a recurring
/// total as "/mo".
InvoiceBreakdownData previewInvoiceBreakdown(
  PreviewInvoice preview, {
  String? amountSuffix,
}) {
  return InvoiceBreakdownData(
    lines: preview.lines.map((l) {
      // Negative when the line is discounted (net below list).
      final discount = l.discountedAmount - l.amount;
      return InvoiceLineItem(
        description: l.description ?? 'Line item',
        amount: l.amount,
        discountAmount: discount != 0 ? discount : null,
      );
    }).toList(),
    total: preview.total,
    currency: preview.currency,
    amountSuffix: amountSuffix,
  );
}

/// Builds the before→after [InvoiceBreakdownData] for a discount
/// add/remove preview from the member's **current** recurring invoice
/// and the **staged next** preview (both [PreviewInvoice]s with lines
/// keyed by `stripeSubscriptionItemId`).
///
/// Each next line carries its undiscounted (list) price ([amount]) and
/// the aggregate discount on it (`discountedAmount − amount`); its net
/// before→after is `currentNet → nextNet`, where the current net comes
/// from the matching current line (fallback: the list price when there
/// is no current line). The Monthly total is `currentTotal → nextTotal`
/// (fallback [fallbackCurrentMonthly]). The shared [InvoiceBreakdown]
/// renders all of it — undiscounted price, discount, line old → new,
/// and the Monthly old → new with a Difference row.
InvoiceBreakdownData comparisonBreakdownFromPair({
  required PreviewInvoice? current,
  required PreviewInvoice next,
  int? fallbackCurrentMonthly,
  String totalLabel = 'Monthly',
  String amountSuffix = '/mo',
}) {
  // Current post-discount line nets, keyed by sub-item.
  final currentBySi = <String, int>{
    for (final l in current?.lines ?? const <PreviewInvoiceLine>[])
      if (l.stripeSubscriptionItemId != null)
        l.stripeSubscriptionItemId!: l.discountedAmount,
  };

  final lines = <InvoiceLineItem>[];
  for (final l in next.lines) {
    final qty = l.quantity;
    final label = (qty != null && qty > 1)
        ? '${l.description ?? 'Line item'}  ×$qty'
        : (l.description ?? 'Line item');
    // Negative when the line is discounted (net below list).
    final discount = l.discountedAmount - l.amount;
    // Prior net for this line; fall back to the list amount when there
    // is no matching current line (e.g. no live subscription yet).
    final previousNet =
        currentBySi[l.stripeSubscriptionItemId] ?? l.amount;
    lines.add(
      InvoiceLineItem(
        description: label,
        amount: l.amount,
        discountAmount: discount != 0 ? discount : null,
        previousAmount: previousNet,
      ),
    );
  }

  return InvoiceBreakdownData(
    lines: lines,
    total: next.total,
    currency: next.currency,
    previousTotal: current?.total ?? fallbackCurrentMonthly,
    totalLabel: totalLabel,
    amountSuffix: amountSuffix,
  );
}

/// The recurring breakdown when a change removes the LAST membership on
/// the subscription: there is no "next" invoice because the subscription
/// ends, so the new monthly is **$0** shown against the current
/// ([current] / [fallbackCurrentMonthly]) — old → $0 with a Difference
/// row, rather than an empty "nothing to show" state.
InvoiceBreakdownData endingBreakdown({
  required PreviewInvoice? current,
  int? fallbackCurrentMonthly,
  String totalLabel = 'Monthly',
  String amountSuffix = '/mo',
}) {
  return InvoiceBreakdownData(
    lines: const [],
    total: 0,
    currency: current?.currency ?? 'usd',
    previousTotal: current?.total ?? fallbackCurrentMonthly,
    totalLabel: totalLabel,
    amountSuffix: amountSuffix,
  );
}
