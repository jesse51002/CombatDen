import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
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
                      .map((p) => _buildRow(p))
                      .toList(),
                ),
        ),
      ],
    );
  }

  AppDataTableRow _buildRow(PaymentRecord payment) {
    final dateFmt = DateFormat('M/dd/yyyy');

    return AppDataTableRow(
      cells: [
        Text(
          '${payment.itemType ?? 'Payment'} - '
          '\$${payment.amountPaid.toStringAsFixed(0)}',
          style: DesignConstants.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          dateFmt.format(payment.time.toLocal()),
          style: DesignConstants.h3,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            label:
                'View invoice for ${payment.itemType ?? 'payment'}'
                ' on ${dateFmt.format(payment.time.toLocal())}',
            child: AppOutlineButton(
              text: 'Invoice',
              onPressed: () {
                // TODO: View/download invoice
              },
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
}
