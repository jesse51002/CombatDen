import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_format.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_attribution.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';

/// The one shared invoice viewer. Takes up to three optional invoices —
/// [dueNow] (charged today), [recurring] (the steady-state monthly), and
/// [recurringPrev] (the current monthly to compare against) — and renders
/// each present section through the shared [InvoiceBreakdown] with a strong
/// section heading, line items + discounts, and a total.
///
/// When [recurringPrev] (or [recurringFallbackMonthly]) is supplied the
/// recurring section is a current → new comparison (old → new per line, a
/// Monthly old → new total, and a Difference row); otherwise it is the
/// plain new monthly. Every preview surface composes this — membership
/// start, discount add/remove, … — so the look is identical everywhere.
/// [InvoicePreviewSection] fetches the invoices and supplies the card +
/// loading/error chrome around it.
class InvoicePreview extends StatelessWidget {
  final PreviewInvoice? dueNow;
  final PreviewInvoice? recurring;
  final PreviewInvoice? recurringPrev;

  /// Fallback current monthly (minor units) for the comparison when
  /// [recurringPrev] can't be loaded.
  final int? recurringFallbackMonthly;

  /// Optional attribution — whose invoice this is. When [payerName] is set
  /// it renders once, as an avatar+name header on the FIRST visible section
  /// (so a due-now + recurring pair reads as one person's invoice, not two).
  final String? payerName;
  final String? payerPhotoUrl;

  final String dueNowLabel;
  final String emptyLabel;

  const InvoicePreview({
    super.key,
    this.dueNow,
    this.recurring,
    this.recurringPrev,
    this.recurringFallbackMonthly,
    this.payerName,
    this.payerPhotoUrl,
    this.dueNowLabel = 'What will be charged today',
    this.emptyLabel = 'No charge today.',
  });

  bool get _comparative =>
      recurringPrev != null || recurringFallbackMonthly != null;

  /// The attribution header for the first visible section, or null when no
  /// payer was supplied.
  InvoiceAttribution? get _attribution {
    final name = payerName;
    if (name == null) return null;
    return InvoiceAttribution(
      name: name,
      photoUrl: payerPhotoUrl,
      caption: 'Billed to',
    );
  }

  @override
  Widget build(BuildContext context) {
    final due = dueNow;
    final rec = recurring;
    // Show the recurring section when there's a new invoice OR a "before"
    // to compare against. A "before" with no "after" means the change
    // removed the last membership — the subscription ends, so the new
    // monthly is $0 (not an empty "nothing to show").
    final showRecurring = rec != null || _comparative;
    if (due == null && !showRecurring) {
      return Text(
        emptyLabel,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (due != null)
          InvoiceBreakdown(
            data: previewInvoiceBreakdown(due),
            // Attribution rides the first section only.
            attribution: _attribution,
            headerCaption: dueNowLabel,
            strongHeaderCaption: true,
          ),
        if (showRecurring)
          InvoiceBreakdown(
            data: _recurringData(rec),
            // First section iff there was no due-now above it.
            attribution: due == null ? _attribution : null,
            // "Then, each month" reads as a sequence after a due-now
            // charge; with no due-now it's just the monthly payment.
            headerCaption:
                due != null ? 'Then, each month' : 'Monthly Payment',
            strongHeaderCaption: true,
            headerMeta: rec?.nextPaymentAt == null
                ? null
                : formatDay(rec!.nextPaymentAt),
          ),
      ],
    );
  }

  /// The recurring breakdown: the new invoice (comparison vs plain), or —
  /// when there is no new invoice but a "before" exists — the
  /// subscription-ending $0 comparison.
  InvoiceBreakdownData _recurringData(PreviewInvoice? rec) {
    if (rec != null) {
      return _comparative
          ? comparisonBreakdownFromPair(
              current: recurringPrev,
              next: rec,
              fallbackCurrentMonthly: recurringFallbackMonthly,
            )
          : previewInvoiceBreakdown(rec, amountSuffix: '/mo');
    }
    return endingBreakdown(
      current: recurringPrev,
      fallbackCurrentMonthly: recurringFallbackMonthly,
    );
  }
}
