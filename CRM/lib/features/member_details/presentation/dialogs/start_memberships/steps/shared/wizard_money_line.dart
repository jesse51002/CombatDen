import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// One money line: what it is on the left, what it costs on the right.
///
/// The amount arrives in MINOR UNITS and is formatted here, at the render
/// layer, through the one shared helper — no call site divides by a hundred.
/// [total] is the summary rung under a hairline: same row, heavier ink, so a
/// column of parts and their sum are visibly the same list.
class WizardMoneyLine extends StatelessWidget {
  final String label;
  final int amountMinorUnits;
  final String currency;

  /// The bold summary rung at the bottom of a group.
  final bool total;

  const WizardMoneyLine({
    super.key,
    required this.label,
    required this.amountMinorUnits,
    required this.currency,
    this.total = false,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final labelStyle = total
        ? scale.label
        : scale.caption.copyWith(color: DesignConstants.text2nd);
    final amountStyle = total ? scale.label : scale.caption;
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            label,
            style: labelStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          formatMinorUnits(amountMinorUnits, currency: currency),
          style: amountStyle,
        ),
      ],
    );
  }
}
