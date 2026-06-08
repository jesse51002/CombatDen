import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';

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

  /// When true, the header caption renders in the strong (ink) title
  /// style — matching a section heading — instead of the default muted
  /// style. Used for the recurring "Then, each month" section.
  final bool strongHeaderCaption;

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

class _Header extends StatelessWidget {
  final String caption;
  final String? meta;
  final String? statusLabel;
  final InvoiceChipTone statusTone;
  final bool strongCaption;

  const _Header({
    required this.caption,
    required this.statusTone,
    this.meta,
    this.statusLabel,
    this.strongCaption = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          caption,
          style: strongCaption
              ? DesignConstants.h3
              : DesignConstants.h3.copyWith(
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
  final bool indent;

  /// When non-null (and ≠ [amount]) the amount renders as a
  /// before→after cluster: struck-through [previousAmount], an
  /// arrow, then [amount]. Null → a single amount (the plain path).
  final int? previousAmount;

  /// Optional per-amount suffix, e.g. "/mo" for a recurring total.
  final String? suffix;

  const _LineRow({
    required this.label,
    required this.amount,
    required this.currency,
    this.emphasised = false,
    this.muted = false,
    this.indent = false,
    this.previousAmount,
    this.suffix,
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
          child: Padding(
            padding: EdgeInsets.only(
              left: indent ? DesignConstants.spacingLarge : 0,
            ),
            child: Text(
              label,
              style: style,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        _AmountCluster(
          amount: amount,
          previousAmount: previousAmount,
          currency: currency,
          style: style,
          suffix: suffix,
        ),
      ],
    );
  }
}

/// The right-hand amount of a line. A single amount in the plain
/// path; a struck-through old → arrow → new cluster when a
/// [previousAmount] that differs is supplied.
class _AmountCluster extends StatelessWidget {
  final int amount;
  final int? previousAmount;
  final String currency;
  final TextStyle style;
  final String? suffix;

  const _AmountCluster({
    required this.amount,
    required this.currency,
    required this.style,
    this.previousAmount,
    this.suffix,
  });

  String _fmt(int value) =>
      '${formatMinorUnits(value, currency: currency)}${suffix ?? ''}';

  @override
  Widget build(BuildContext context) {
    final prev = previousAmount;
    if (prev == null || prev == amount) {
      return Text(_fmt(amount), style: style);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          _fmt(prev),
          style: style.copyWith(
            color: DesignConstants.text2nd,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        Text(
          '→',
          style: style.copyWith(color: DesignConstants.text2nd),
        ),
        Text(_fmt(amount), style: style),
      ],
    );
  }
}

/// The signed delta row under a comparison total: "$X more" when
/// the new total is higher, "$X less" when lower.
class _DifferenceRow extends StatelessWidget {
  final int amount;
  final String currency;

  const _DifferenceRow({
    required this.amount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final word = amount < 0 ? 'less' : 'more';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text('Difference', style: DesignConstants.p),
        ),
        Text(
          '${formatMinorUnits(amount.abs(), currency: currency)}'
          ' $word',
          style: DesignConstants.p,
        ),
      ],
    );
  }
}

/// One payment attempt row: the method + time on the left, a
/// status chip and the signed amount on the right.
class _AttemptRow extends StatelessWidget {
  final InvoiceAttemptLine attempt;
  final String currency;

  const _AttemptRow({
    required this.attempt,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(
                attempt.method,
                style: DesignConstants.p,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                attempt.timeLabel,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            InvoiceChip(
              label: attempt.statusLabel,
              tone: attempt.statusTone,
            ),
            Text(
              formatMinorUnits(attempt.amount, currency: currency),
              style: DesignConstants.p,
            ),
          ],
        ),
      ],
    );
  }
}
