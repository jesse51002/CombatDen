import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/charge_status.dart';

/// Status pill for a historical charge — coloured by
/// success / pending / failure.
class ChargeStatusChip extends StatelessWidget {
  final ChargeStatus status;

  const ChargeStatusChip({
    super.key,
    required this.status,
  });

  Color _colorFor(ChargeStatus s) {
    switch (s) {
      case ChargeStatus.succeeded:
        return DesignConstants.goodGreen;
      case ChargeStatus.pending:
        return DesignConstants.okYellow;
      case ChargeStatus.failed:
        return DesignConstants.badRed;
      case ChargeStatus.unknown:
        return DesignConstants.text2nd;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
      ),
      child: Text(
        status.displayLabel,
        style: DesignConstants.pSmall.copyWith(
          color: color,
        ),
      ),
    );
  }
}
