import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_attempt_line.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_attribution.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';

part 'invoice_breakdown_rows.dart';

/// Renders the cost "formula" for any invoice-shaped
/// entity — a preview, a historical payment, a finalized
/// invoice, or a before/after comparison — from a normalized
/// [InvoiceBreakdownData]. Background is transparent: the
/// parent (a dialog body, a card) owns the surface.
///
/// A reusable billing primitive. Each member-detail billing
/// surface builds the [data] from its own backend model and
/// composes this widget, so they all share one look. When the
/// comparison fields on [data] (`previousAmount` per line,
/// `previousTotal`) are absent it renders a plain invoice; when
/// present it renders the before→after (old → new) treatment.
/// The private row widgets live in `invoice_breakdown_rows.dart`.
class InvoiceBreakdown extends StatelessWidget {
  final InvoiceBreakdownData data;

  /// Optional attribution header (avatar + name) shown ABOVE everything
  /// else — whose invoice this is. Every billing surface passes one so an
  /// invoice display always says who it belongs to (the payer whose card /
  /// subscription it bills). Omit only where the parent already shows the
  /// person.
  final InvoiceAttribution? attribution;

  /// Optional header row shown above the line items — a
  /// caption (e.g. "Payment" / "Refund") on the left and
  /// an optional timestamp + status chip on the right. Used
  /// for historical charges; omit for a live preview.
  final String? headerCaption;
  final String? headerMeta;
  final String? statusLabel;
  final InvoiceChipTone statusTone;

  /// When true, the header caption + meta render in the strong h2
  /// section-title style, instead of the default muted style. Used for
  /// the recurring "Then, each month" section.
  final bool strongHeaderCaption;

  /// When non-null, a full-width destructive "Refund"
  /// button is rendered at the bottom. The parent confirms
  /// before acting — this only surfaces the affordance.
  final VoidCallback? onRefundPressed;
  final String refundLabel;

  const InvoiceBreakdown({
    super.key,
    required this.data,
    this.attribution,
    this.headerCaption,
    this.headerMeta,
    this.statusLabel,
    this.statusTone = InvoiceChipTone.neutral,
    this.strongHeaderCaption = false,
    this.onRefundPressed,
    this.refundLabel = 'Refund',
  });

  /// The rows a single line contributes: its (undiscounted in
  /// comparison mode) amount, then — only in comparison mode — an
  /// indented "Discount" row and the line's net old → new row.
  List<Widget> _lineRows(InvoiceLineItem l) {
    final rows = <Widget>[
      _LineRow(
        label: l.description,
        amount: l.amount,
        currency: data.currency,
      ),
    ];
    final discount = l.discountAmount;
    if (discount != null && discount != 0) {
      rows.add(
        _LineRow(
          label: 'Discount',
          amount: discount,
          currency: data.currency,
          muted: true,
          indent: true,
        ),
      );
    }
    final prev = l.previousAmount;
    if (prev != null) {
      final newNet = l.amount + (l.discountAmount ?? 0);
      if (prev != newNet) {
        rows.add(
          _LineRow(
            label: 'Net',
            amount: newNet,
            previousAmount: prev,
            currency: data.currency,
            indent: true,
          ),
        );
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final prevTotal = data.previousTotal;
    final showDifference =
        prevTotal != null && data.total != prevTotal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        ?attribution,
        if (headerCaption != null)
          _Header(
            caption: headerCaption!,
            meta: headerMeta,
            statusLabel: statusLabel,
            statusTone: statusTone,
            strongCaption: strongHeaderCaption,
          ),
        ...data.lines.expand(_lineRows),
        ...data.appliedDiscounts.map(
          (d) => _LineRow(
            label: d.label,
            amount: d.amount,
            currency: data.currency,
            muted: true,
            indent: true,
          ),
        ),
        if (data.subtotal != null)
          _LineRow(
            label: 'Subtotal',
            amount: data.subtotal!,
            currency: data.currency,
            muted: true,
          ),
        Divider(
          color: DesignConstants.divider,
          height: 1,
        ),
        _LineRow(
          label: data.isRefund ? 'Refunded' : data.totalLabel,
          amount: data.total,
          currency: data.currency,
          emphasised: data.refundedAmount == 0,
          previousAmount: data.previousTotal,
          suffix: data.amountSuffix,
        ),
        if (showDifference)
          _DifferenceRow(
            amount: data.total - prevTotal,
            currency: data.currency,
          ),
        if (data.refundedAmount > 0) ...[
          _LineRow(
            label: 'Refunded',
            amount: -data.refundedAmount,
            currency: data.currency,
            muted: true,
          ),
          _LineRow(
            label: 'Net',
            amount: data.total - data.refundedAmount,
            currency: data.currency,
            emphasised: true,
          ),
        ],
        if (data.attempts.isNotEmpty) ...[
          Divider(
            color: DesignConstants.divider,
            height: 1,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                'Payment attempts',
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
              ...data.attempts.map(
                (a) => _AttemptRow(
                  attempt: a,
                  currency: data.currency,
                ),
              ),
            ],
          ),
        ],
        if (onRefundPressed != null)
          AppOutlineButton(
            fullWidth: true,
            text: refundLabel,
            onPressed: onRefundPressed,
            borderColor: DesignConstants.badRed,
            textColor: DesignConstants.badRed,
            borderRadius: DesignConstants.radiusSmall,
          ),
      ],
    );
  }
}
