import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_result_item.dart';
import 'package:crm/features/check_in/data/models/check_in_warning.dart';
import 'package:crm/features/check_in/data/models/class_check_in_status.dart';

/// One per-member result line in the batch breakdown: checked in (✓ "+N pts"),
/// already in, needs confirmation (not recorded — the gate warned), or failed
/// (✗ — reason), labelled with the member's name. Any non-blocking gate
/// warnings — including a `needsConfirmation` member's reasons — show as a
/// small note beneath the detail.
class BatchCheckInResultRow extends StatelessWidget {
  final BatchCheckInResultItem item;
  final String memberName;

  const BatchCheckInResultRow({
    super.key,
    required this.item,
    required this.memberName,
  });

  Color get _color => switch (item.status) {
        ClassCheckInStatus.checkedIn ||
        ClassCheckInStatus.alreadyCheckedIn =>
          DesignConstants.goodGreen,
        ClassCheckInStatus.needsConfirmation => DesignConstants.okYellow,
        ClassCheckInStatus.failed => DesignConstants.badRed,
        _ => DesignConstants.text2nd,
      };

  IconData get _icon => switch (item.status) {
        ClassCheckInStatus.checkedIn ||
        ClassCheckInStatus.alreadyCheckedIn =>
          Symbols.check_circle_sharp,
        ClassCheckInStatus.needsConfirmation => Symbols.warning_sharp,
        ClassCheckInStatus.failed => Symbols.cancel_sharp,
        _ => Symbols.do_not_disturb_on_sharp,
      };

  String get _detail => switch (item.status) {
        ClassCheckInStatus.checkedIn => '+${item.pointsAwarded} pts',
        ClassCheckInStatus.alreadyCheckedIn =>
          'Already checked in — no change',
        ClassCheckInStatus.skipped =>
          'Skipped — ${CheckInWarning.humanize(item.reason)}',
        ClassCheckInStatus.needsConfirmation =>
          'Not recorded — needs confirmation',
        _ => item.reason ?? 'Could not be checked in',
      };

  @override
  Widget build(BuildContext context) {
    final warnings =
        item.warnings.isEmpty ? null : CheckInWarning.summarize(item.warnings);
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(color: DesignConstants.divider),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _icon,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeLarge,
            color: _color,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(memberName, style: DesignConstants.pSemibold),
                Text(
                  _detail,
                  style: DesignConstants.pSmall.copyWith(color: _color),
                ),
                if (warnings != null)
                  Text(
                    warnings,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.okYellow,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            item.status.displayLabel,
            style: DesignConstants.pSmallSemibold.copyWith(color: _color),
          ),
        ],
      ),
    );
  }
}
