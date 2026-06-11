import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';

/// The preview step's single combined "Total due today"
/// row — the one number the desk reads out loud. Sums the
/// one-time invoice and the recurring amount due now, and
/// renders heavier (strong h2) than the per-card totals so
/// it reads as the bottom line, even when it's one charge
/// or $0.
class TotalDueTodayRow extends StatelessWidget {
  /// The combined amount in minor units (cents).
  final int amount;

  /// ISO 4217 currency code from the preview invoices.
  final String currency;

  const TotalDueTodayRow({
    super.key,
    required this.amount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Expanded(
            child: Text(
              'Total due today',
              style: DesignConstants.h2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatMinorUnits(amount, currency: currency),
            style: DesignConstants.h2,
          ),
        ],
      ),
    );
  }
}
