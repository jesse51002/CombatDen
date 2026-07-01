import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/signup_batch_result.dart';

/// One per-member result line in the "Reserve members" breakdown: reserved
/// (✓), already reserved (✓, no change), or failed (✗ — [item]'s `reason`,
/// e.g. "Class is full"). Mirrors `BatchCheckInResultRow`'s shape for the
/// simpler reservation outcome set (no warnings / needs-confirmation).
class SignupResultRow extends StatelessWidget {
  final SignupBatchResultItem item;
  final String memberName;

  const SignupResultRow({
    super.key,
    required this.item,
    required this.memberName,
  });

  Color get _color => switch (item.status) {
        SignupBatchStatus.signedUp ||
        SignupBatchStatus.alreadySignedUp =>
          DesignConstants.goodGreen,
        SignupBatchStatus.failed => DesignConstants.badRed,
      };

  IconData get _icon => switch (item.status) {
        SignupBatchStatus.signedUp ||
        SignupBatchStatus.alreadySignedUp =>
          Symbols.check_circle_sharp,
        SignupBatchStatus.failed => Symbols.cancel_sharp,
      };

  String get _detail => switch (item.status) {
        SignupBatchStatus.signedUp => 'Reserved',
        SignupBatchStatus.alreadySignedUp => 'Already reserved — no change',
        SignupBatchStatus.failed =>
          item.reason ?? 'Couldn’t reserve a spot',
      };

  @override
  Widget build(BuildContext context) {
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
