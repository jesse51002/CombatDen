import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/presentation/dialogs/payment_invoice_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// Beyond this many payments the table scrolls inside a fixed-height
/// box instead of growing the card — so a long history doesn't stretch
/// the membership column (and, via the equal-height grid, the left
/// column). At or below it the table renders at its natural height.
const int _kInlineRowLimit = 6;
const double _kScrollBoxHeight = 360;

/// Payment history for the membership carousel. Each row
/// opens the full invoice (via [PaymentInvoiceDialog]),
/// which carries the refund affordance. A long history
/// scrolls within a capped box (header stays pinned).
class PaymentHistorySection extends StatelessWidget {
  final List<PaymentRecord> payments;

  const PaymentHistorySection({
    super.key,
    required this.payments,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Payment history',
      child: payments.isEmpty
          ? _Empty()
          : payments.length <= _kInlineRowLimit
              ? _table(context, scroll: false)
              : SizedBox(
                  height: _kScrollBoxHeight,
                  child: _table(context, scroll: true),
                ),
    );
  }

  /// The table. When [scroll] is true it owns a fixed-height
  /// internal scroll (sticky header); otherwise it renders at
  /// its natural height inside the page scroll.
  Widget _table(
    BuildContext context, {
    required bool scroll,
  }) {
    return AppDataTable(
      shrinkWrap: !scroll,
      stickyHeader: scroll,
      showBackground: true,
      columns: const [
        AppDataTableColumn(
          label: 'Name',
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Date',
          minWidth: 110,
        ),
        AppDataTableColumn(
          label: '',
          minWidth: 92,
        ),
      ],
      rows: payments
          .map((p) => _row(context, p))
          .toList(),
    );
  }

  AppDataTableRow _row(
    BuildContext context,
    PaymentRecord payment,
  ) {
    final label = _label(payment);
    return AppDataTableRow(
      cells: [
        Text(
          label,
          style: DesignConstants.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          formatDay(payment.chargeTime),
          style: DesignConstants.h3,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: AppOutlineButton(
            text: 'Invoice',
            borderRadius: DesignConstants.radiusSmall,
            textStyle: DesignConstants.pSmall,
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingSmall,
              vertical: DesignConstants.spacingTiny,
            ),
            onPressed: () => PaymentInvoiceDialog.show(
              context: context,
              payment: payment,
            ),
          ),
        ),
      ],
    );
  }

  /// "Monthly Pro · $50" or "Refund · -$20".
  String _label(PaymentRecord payment) {
    final name = payment.lineItems.isNotEmpty
        ? payment.lineItems.first.name
        : payment.kind.displayLabel;
    final amount = formatMinorUnits(
      payment.amount,
      currency: payment.currency,
    );
    return '$name · $amount';
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        DesignConstants.paddingBig,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Center(
        child: Text(
          'No payments yet',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}
