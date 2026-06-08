import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_format.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';

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

  final String dueNowLabel;
  final String recurringLabel;
  final String emptyLabel;

  const InvoicePreview({
    super.key,
    this.dueNow,
    this.recurring,
    this.recurringPrev,
    this.recurringFallbackMonthly,
    this.dueNowLabel = 'What will be charged today',
    this.recurringLabel = 'Then, each month',
    this.emptyLabel = 'No charge today.',
  });

  bool get _comparative =>
      recurringPrev != null || recurringFallbackMonthly != null;

  @override
  Widget build(BuildContext context) {
    final due = dueNow;
    final rec = recurring;
    if (due == null && rec == null) {
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
            headerCaption: dueNowLabel,
            strongHeaderCaption: true,
          ),
        if (rec != null)
          InvoiceBreakdown(
            data: _comparative
                ? comparisonBreakdownFromPair(
                    current: recurringPrev,
                    next: rec,
                    fallbackCurrentMonthly: recurringFallbackMonthly,
                  )
                : previewInvoiceBreakdown(rec, amountSuffix: '/mo'),
            headerCaption: recurringLabel,
            strongHeaderCaption: true,
            headerMeta: rec.nextPaymentAt == null
                ? null
                : formatDay(rec.nextPaymentAt),
          ),
      ],
    );
  }
}
