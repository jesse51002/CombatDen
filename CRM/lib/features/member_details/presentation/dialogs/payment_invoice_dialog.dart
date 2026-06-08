import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/data/models/charge_kind.dart';
import 'package:crm/features/member_details/data/models/charge_status.dart';
import 'package:crm/features/member_details/data/models/invoice_attempt.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/presentation/dialogs/refund_charge_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_attempt_line.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// Shows a historical [PaymentRecord] as a full invoice via
/// the shared [InvoiceBreakdown]. A refund affordance is
/// rendered only for a succeeded, non-refund charge; it
/// routes through a [BillingConfirmationDialog] and then
/// dispatches [RefundChargeRequested].
///
/// NOTE: the merged contract has no refund endpoint — the
/// repository's refund call targets an assumed path that
/// will 404 until the backend ships it. The frozen
/// [RefundChargeRequested] event exists, so the seam is
/// wired; a real failure surfaces through the bloc's
/// `actionError` path.
class PaymentInvoiceDialog extends StatelessWidget {
  final PaymentRecord payment;

  const PaymentInvoiceDialog({
    super.key,
    required this.payment,
  });

  static Future<void> show({
    required BuildContext context,
    required PaymentRecord payment,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: PaymentInvoiceDialog(payment: payment),
      ),
    );
  }

  bool get _isRefund => payment.kind == ChargeKind.refund;

  /// Refundable only when this is a succeeded payment (not
  /// already a refund, not pending/failed) with an
  /// un-refunded balance left.
  bool get _canRefund =>
      !_isRefund &&
      payment.status == ChargeStatus.succeeded &&
      payment.netAmount > 0;

  /// Adapts the [PaymentRecord] into the shared,
  /// presentation-only [InvoiceBreakdownData] shape. Falls
  /// back to a single line when the record carries no line
  /// items.
  InvoiceBreakdownData get _data {
    final lines = payment.lineItems.isNotEmpty
        ? payment.lineItems
            .map(
              (l) => InvoiceLineItem(
                description: l.quantity > 1
                    ? '${l.name} ×${l.quantity}'
                    : l.name,
                amount: l.amount,
              ),
            )
            .toList()
        : [
            InvoiceLineItem(
              description: _isRefund ? 'Refund' : 'Payment',
              amount: payment.amount,
            ),
          ];
    return InvoiceBreakdownData(
      lines: lines,
      total: payment.amount,
      currency: payment.currency,
      isRefund: _isRefund,
      refundedAmount: payment.refundedAmount,
      appliedDiscounts: payment.appliedDiscounts
          .map(
            (d) => InvoiceDiscount(
              label: 'Discount',
              amount: -d.amountOff,
            ),
          )
          .toList(),
      attempts: payment.attempts
          .map(
            (a) => InvoiceAttemptLine(
              method: _attemptMethod(a),
              timeLabel: formatDay(a.chargeTime),
              amount: a.amount,
              statusLabel: _attemptStatusLabel(a),
              statusTone: _attemptStatusTone(a),
            ),
          )
          .toList(),
    );
  }

  /// "•••• 4242" for a card, "Cash" for cash, else the method
  /// type (or "—" when we never captured one — e.g. a failed
  /// attempt, whose card isn't on the webhook payload).
  String _attemptMethod(InvoiceAttempt a) {
    final last4 = a.cardLastFour;
    if (last4 != null && last4.isNotEmpty) {
      return '•••• $last4';
    }
    final type = a.paymentMethodType;
    if (type == null || type.isEmpty) return '—';
    if (type == 'cash') return 'Cash';
    if (type == 'card') return 'Card';
    return type;
  }

  String _attemptStatusLabel(InvoiceAttempt a) =>
      a.kind == ChargeKind.refund
          ? 'Refunded'
          : a.status.displayLabel;

  InvoiceChipTone _attemptStatusTone(InvoiceAttempt a) {
    if (a.kind == ChargeKind.refund) {
      return InvoiceChipTone.neutral;
    }
    return switch (a.status) {
      ChargeStatus.succeeded => InvoiceChipTone.good,
      ChargeStatus.pending => InvoiceChipTone.warning,
      ChargeStatus.failed => InvoiceChipTone.bad,
      ChargeStatus.unknown => InvoiceChipTone.neutral,
    };
  }

  /// Closes the invoice, then routes the refund through the
  /// shared [RefundChargeDialog] (confirmation +
  /// [RefundChargeRequested]) so the refund flow lives in
  /// one place.
  void _onRefund(BuildContext context) {
    Navigator.of(context).pop();
    RefundChargeDialog.show(
      context: context,
      charge: payment,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: _isRefund ? 'Refund' : 'Invoice',
      body: InvoiceBreakdown(
        data: _data,
        headerCaption: _isRefund ? 'Refund' : 'Payment',
        headerMeta: formatDay(payment.chargeTime),
        strongHeaderCaption: true,
        statusLabel: payment.status.displayLabel,
        statusTone: _statusTone,
        onRefundPressed:
            _canRefund ? () => _onRefund(context) : null,
      ),
    );
  }

  InvoiceChipTone get _statusTone {
    return switch (payment.status) {
      ChargeStatus.succeeded => InvoiceChipTone.good,
      ChargeStatus.pending => InvoiceChipTone.warning,
      ChargeStatus.failed => InvoiceChipTone.bad,
      ChargeStatus.unknown => InvoiceChipTone.neutral,
    };
  }
}
