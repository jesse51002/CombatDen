import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_breakdown_data.dart';

/// Shows a historical payment record as a full invoice.
/// The Refund action (rendered by [InvoiceBreakdown] when
/// the record is a succeeded non-refund charge) routes
/// through a confirmation and dispatches
/// [RefundChargeRequested].
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

  Future<void> _onRefund(BuildContext context) async {
    final amount = formatMinorUnits(
      payment.amount,
      currency: payment.currency,
    );
    final confirmed =
        await BillingConfirmationDialog.show(
      context: context,
      title: 'Confirm refund',
      summary:
          'Issues a $amount refund back to the card used '
          'for this charge.',
      effects: [
        BillingEffect(
          icon: Symbols.undo_sharp,
          text: '$amount refunded to card.',
          iconColor: DesignConstants.badRed,
        ),
        const BillingEffect(
          icon: Symbols.schedule_sharp,
          text: 'Typically posts within 5–10 business days.',
        ),
      ],
      affected: const [],
      confirmLabel: 'Refund $amount',
      confirmColor: DesignConstants.badRed,
      warning: 'Refunds cannot be reversed from the CRM.',
    );
    if (!confirmed || !context.mounted) return;
    context.read<MemberDetailBloc>().add(
          RefundChargeRequested(
            chargeId: payment.chargeId,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Invoice',
      body: InvoiceBreakdown(
        data: InvoiceBreakdownData.fromPayment(payment),
        onRefundPressed: () => _onRefund(context),
      ),
    );
  }
}
