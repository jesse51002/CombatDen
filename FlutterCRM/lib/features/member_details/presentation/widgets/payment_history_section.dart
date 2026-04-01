import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';

/// Payment history table with fixed-height scrollable
/// body.
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
      children: [
        Text(
          'Payment History',
          style: DesignConstants.h3,
        ),
        const SizedBox(
          height: DesignConstants.spacingMedium,
        ),
        Container(
          decoration: BoxDecoration(
            color: DesignConstants.cardBackground,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusSmall,
            ),
          ),
          child: Column(
            children: [
              // Header
              _HeaderRow(),
              const Divider(
                height: 1,
                color: DesignConstants.buttonStroke,
              ),
              // Scrollable body
              SizedBox(
                height: 240,
                child: payments.isEmpty
                    ? Center(
                        child: Text(
                          'No payments yet',
                          style: DesignConstants.p.copyWith(
                            color: DesignConstants.text2nd,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: payments.length,
                        separatorBuilder: (_, _) =>
                            const Divider(
                          height: 1,
                          color: DesignConstants.buttonStroke,
                        ),
                        itemBuilder: (_, index) =>
                            _PaymentRow(
                          payment: payments[index],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal:
            DesignConstants.spacingMedium,
        vertical:
            DesignConstants.spacingSmall,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Name',
              style: DesignConstants.h3.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Date',
              style: DesignConstants.h3.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ),
          const Expanded(
            child: SizedBox(),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final PaymentRecord payment;

  const _PaymentRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('M/dd/yyyy');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal:
            DesignConstants.spacingMedium,
        vertical:
            DesignConstants.spacingSmall,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              '${payment.itemType ?? 'Payment'} - '
              '\$${payment.amountPaid.toStringAsFixed(0)}',
              style: DesignConstants.p,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              dateFmt.format(payment.time.toLocal()),
              style: DesignConstants.p,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                label:
                    'View invoice for ${payment.itemType ?? 'payment'}'
                    ' on ${dateFmt.format(payment.time.toLocal())}',
                child: OutlinedButton(
                  onPressed: () {
                    // TODO: View/download invoice
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DesignConstants.text,
                    side: const BorderSide(
                      color: DesignConstants.buttonStroke,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        DesignConstants.radiusBig,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignConstants
                          .spacingSmall
                          ,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Invoice',
                    style: DesignConstants.pSmall,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
