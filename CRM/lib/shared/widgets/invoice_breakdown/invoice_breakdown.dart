import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';

/// Renders the cost "formula" for any invoice-shaped
/// entity — a preview, a historical payment, or a
/// finalized invoice — from a normalized
/// [InvoiceBreakdownData]. Background is transparent: the
/// parent (a dialog body, a card) owns the surface.
///
/// A reusable billing primitive. The member-detail billing
/// dialogs (a later workflow) build the [data] from their
/// own backend models and compose this widget.
class InvoiceBreakdown extends StatelessWidget {
  final InvoiceBreakdownData data;

  /// Optional header row shown above the line items — a
  /// caption (e.g. "Payment" / "Refund") on the left and
  /// an optional timestamp + status chip on the right. Used
  /// for historical charges; omit for a live preview.
  final String? headerCaption;
  final String? headerMeta;
  final String? statusLabel;
  final InvoiceChipTone statusTone;

  /// When non-null, a full-width destructive "Refund"
  /// button is rendered at the bottom. The parent confirms
  /// before acting — this only surfaces the affordance.
  final VoidCallback? onRefundPressed;
  final String refundLabel;

  const InvoiceBreakdown({
    super.key,
    required this.data,
    this.headerCaption,
    this.headerMeta,
    this.statusLabel,
    this.statusTone = InvoiceChipTone.neutral,
    this.onRefundPressed,
    this.refundLabel = 'Refund',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (headerCaption != null)
          _Header(
            caption: headerCaption!,
            meta: headerMeta,
            statusLabel: statusLabel,
            statusTone: statusTone,
          ),
        ...data.lines.map(
          (l) => _LineRow(
            label: l.description,
            amount: l.amount,
            currency: data.currency,
          ),
        ),
        if (data.appliedDiscounts.isNotEmpty)
          Wrap(
            spacing: DesignConstants.spacingSmall,
            runSpacing: DesignConstants.spacingSmall,
            children: data.appliedDiscounts
                .map(
                  (d) => InvoiceChip(
                    label: d.subLabel == null
                        ? d.label
                        : '${d.label} · ${d.subLabel}',
                    tone: InvoiceChipTone.good,
                  ),
                )
                .toList(),
          ),
        if (data.subtotal != null)
          _LineRow(
            label: 'Subtotal',
            amount: data.subtotal!,
            currency: data.currency,
            muted: true,
          ),
        const Divider(
          color: DesignConstants.divider,
          height: 1,
        ),
        _LineRow(
          label: data.isRefund ? 'Refunded' : 'Total',
          amount: data.total,
          currency: data.currency,
          emphasised: true,
        ),
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

class _Header extends StatelessWidget {
  final String caption;
  final String? meta;
  final String? statusLabel;
  final InvoiceChipTone statusTone;

  const _Header({
    required this.caption,
    required this.statusTone,
    this.meta,
    this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          caption,
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            if (meta != null)
              Text(
                meta!,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            if (statusLabel != null)
              InvoiceChip(
                label: statusLabel!,
                tone: statusTone,
              ),
          ],
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  final String label;
  final int amount;
  final String currency;
  final bool emphasised;
  final bool muted;

  const _LineRow({
    required this.label,
    required this.amount,
    required this.currency,
    this.emphasised = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final base =
        emphasised ? DesignConstants.h2 : DesignConstants.p;
    final color =
        muted ? DesignConstants.text2nd : DesignConstants.text;
    final style = base.copyWith(color: color);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            label,
            style: style,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          formatMinorUnits(amount, currency: currency),
          style: style,
        ),
      ],
    );
  }
}
