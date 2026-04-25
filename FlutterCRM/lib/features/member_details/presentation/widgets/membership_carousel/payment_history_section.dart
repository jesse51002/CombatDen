import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/charge_kind.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/invoice/payment_invoice_dialog.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Payment history table inside the membership carousel.
class PaymentHistorySection extends StatelessWidget {
  final List<PaymentRecord> payments;

  const PaymentHistorySection({
    super.key,
    required this.payments,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          'Payment History',
          style: DesignConstants.h2,
        ),
        Expanded(
          child: payments.isEmpty
              ? Center(
                  child: Text(
                    'No payments yet',
                    style:
                        DesignConstants.h2.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                )
              : AppDataTable(
                  stickyHeader: false,
                  showBackground: true,
                  columns: const [
                    AppDataTableColumn(
                      label: 'Name',
                      fill: true,
                    ),
                    AppDataTableColumn(
                      label: 'Date',
                      minWidth: 100,
                    ),
                    AppDataTableColumn(
                      label: '',
                      minWidth: 70,
                    ),
                  ],
                  rows: payments
                      .map((p) => _buildRow(context, p))
                      .toList(),
                ),
        ),
      ],
    );
  }

  AppDataTableRow _buildRow(
    BuildContext context,
    PaymentRecord payment,
  ) {
    final dateFmt = DateFormat('M/dd/yyyy');
    final label = _paymentLabel(payment);

    return AppDataTableRow(
      cells: [
        Text(
          label,
          style: DesignConstants.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          dateFmt.format(payment.chargeTime.toLocal()),
          style: DesignConstants.h3,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            label:
                'View invoice for $label on '
                '${dateFmt.format(payment.chargeTime.toLocal())}',
            child: AppOutlineButton(
              text: 'Invoice',
              onPressed: () =>
                  PaymentInvoiceDialog.show(
                context: context,
                payment: payment,
              ),
              textStyle: DesignConstants.pSmall,
              padding: const EdgeInsets.symmetric(
                horizontal:
                    DesignConstants.spacingSmall,
                vertical: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the display label for a payment row, e.g.
  /// "Monthly Pro - $50" or "Refund - -$20".
  String _paymentLabel(PaymentRecord payment) {
    final name = payment.lineItems.isNotEmpty
        ? payment.lineItems.first.name
        : _kindLabel(payment.kind);
    final amount = formatMinorUnits(
      payment.amount,
      currency: payment.currency,
    );
    return '$name - $amount';
  }

  String _kindLabel(ChargeKind kind) {
    return switch (kind) {
      ChargeKind.payment => 'Payment',
      ChargeKind.refund => 'Refund',
      ChargeKind.unknown => 'Payment',
    };
  }
}
