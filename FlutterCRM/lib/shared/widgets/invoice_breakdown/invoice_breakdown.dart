import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/charge_status.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/invoice_breakdown/charge_status_chip.dart';
import 'package:crm/shared/widgets/invoice_breakdown/discount_chip.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';

/// Renders the cost "formula" for any invoice-shaped
/// entity: a preview, a historical payment, or a
/// finalised invoice. Background is transparent — the
/// parent owns the surface.
class InvoiceBreakdown extends StatelessWidget {
  final InvoiceBreakdownData data;

  /// When non-null, and the invoice is a succeeded,
  /// non-refund historical charge, a full-width Refund
  /// button is rendered at the bottom. The parent is
  /// responsible for confirming before dispatching.
  final VoidCallback? onRefundPressed;

  const InvoiceBreakdown({
    super.key,
    required this.data,
    this.onRefundPressed,
  });

  bool get _canRefund =>
      data.kind == InvoiceKind.historical &&
      !data.isRefund &&
      data.status == ChargeStatus.succeeded &&
      data.chargeId != null &&
      onRefundPressed != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (data.kind == InvoiceKind.historical)
          _HistoricalHeader(data: data),
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
                .map((d) => DiscountChip(discount: d))
                .toList(),
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
          label: data.isRefund ? 'Refunded' : 'Total',
          amount: data.total,
          currency: data.currency,
          emphasised: true,
        ),
        if (_canRefund)
          AppOutlineButton(
            fullWidth: true,
            text: 'Refund',
            onPressed: onRefundPressed,
            borderColor: DesignConstants.badRed,
            textColor: DesignConstants.badRed,
            borderRadius: DesignConstants.radiusSmall,
          ),
      ],
    );
  }
}

class _HistoricalHeader extends StatelessWidget {
  final InvoiceBreakdownData data;

  const _HistoricalHeader({required this.data});

  @override
  Widget build(BuildContext context) {
    final formatted = data.chargeTime != null
        ? DateFormat('MMM d, yyyy · h:mm a').format(
            data.chargeTime!.toLocal(),
          )
        : '';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          data.isRefund ? 'Refund' : 'Payment',
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            if (formatted.isNotEmpty)
              Text(
                formatted,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            if (data.status != null)
              ChargeStatusChip(status: data.status!),
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
    final base = emphasised
        ? DesignConstants.h2
        : DesignConstants.p;
    final color = muted
        ? DesignConstants.text2nd
        : DesignConstants.text;
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
