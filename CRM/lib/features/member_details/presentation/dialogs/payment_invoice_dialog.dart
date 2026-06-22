import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/data/models/charge_kind.dart';
import 'package:crm/features/member_details/data/models/charge_status.dart';
import 'package:crm/features/member_details/data/models/invoice_attempt.dart';
import 'package:crm/features/member_details/data/models/line_item_record.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/core/constants/design_constants.dart';
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
/// routes through the shared [RefundChargeDialog] and then
/// dispatches [RefundChargeRequested]. A failure surfaces
/// through the bloc's `actionError` path.
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

  /// "Paid by {payer} · For {beneficiaries}" — the who-paid / who-for
  /// attribution. The "For" clause is shown only when the bill was for
  /// someone other than the payer (otherwise it's redundant). Null when
  /// there's nothing meaningful to show.
  String? get _attributionLabel {
    final payer = payment.paidByName;
    final others = _beneficiaryNames;
    final parts = <String>[];
    if (payer.isNotEmpty) parts.add('Paid by $payer');
    if (others.isNotEmpty) parts.add('For ${others.join(', ')}');
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

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
                description: _lineDescription(l),
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

  /// "{Plan} ×{qty}" with who the line was FOR appended ("· {names}").
  /// A membership line carries all its co-owners (`ownerLabel`, already
  /// comma-joined); a custom/ad-hoc line has none, so it falls back to the
  /// invoice's beneficiaries (`paid_for`, excluding the payer) — either way
  /// this can be **multiple** people on one line.
  String _lineDescription(LineItemRecord l) {
    final base = l.quantity > 1 ? '${l.name} ×${l.quantity}' : l.name;
    final owner = l.ownerLabel ?? '';
    final forWhom = owner.isNotEmpty ? owner : _beneficiaryNames.join(', ');
    return forWhom.isNotEmpty ? '$base · $forWhom' : base;
  }

  /// The invoice's beneficiaries (`paid_for`) other than the payer — the
  /// people a non-membership line was for. May be several.
  List<String> get _beneficiaryNames => payment.paidFor
      .where((m) => m.memberId != payment.paidByMemberId)
      .map((m) => m.name)
      .where((n) => n.isNotEmpty)
      .toList();

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
    final attribution = _attributionLabel;
    return AppDialog(
      title: _isRefund ? 'Refund' : 'Invoice',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          if (attribution != null)
            Text(
              attribution,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          InvoiceBreakdown(
            data: _data,
            headerCaption: _isRefund ? 'Refund' : 'Payment',
            headerMeta: formatDay(payment.chargeTime),
            strongHeaderCaption: true,
            statusLabel: payment.status.displayLabel,
            statusTone: _statusTone,
            onRefundPressed:
                _canRefund ? () => _onRefund(context) : null,
          ),
        ],
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
