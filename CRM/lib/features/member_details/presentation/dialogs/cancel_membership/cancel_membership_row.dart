import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';

/// One selectable membership row in the cancel checklist — a checkbox, the
/// plan name, a status subtitle (or "for {subject}" for pay-for-others rows),
/// and a "paid by {payer}" line when the payer name is known. A row that is
/// already cancelling is shown for context but is not selectable.
class CancelMembershipRow extends StatelessWidget {
  final CancelTarget target;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const CancelMembershipRow({
    super.key,
    required this.target,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = target.alreadyCancelling;
    final subtitle = target.subtitle;
    final subtitleColor = disabled
        ? DesignConstants.okYellow
        : DesignConstants.text2nd;
    return InkWell(
      onTap: disabled ? null : () => onChanged(!selected),
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.badRed.withValues(alpha: 0.12)
              : DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: selected
                ? DesignConstants.badRed
                : DesignConstants.divider,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? Symbols.check_box_sharp
                  : Symbols.check_box_outline_blank_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeLarge,
              color: disabled
                  ? DesignConstants.text3rd
                  : (selected
                      ? DesignConstants.badRed
                      : DesignConstants.text2nd),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    target.planName,
                    style: DesignConstants.h3,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: DesignConstants.pSmall.copyWith(
                        color: subtitleColor,
                      ),
                    ),
                  if (target.payerName != null)
                    Text(
                      'paid by ${target.payerName}',
                      style: DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text3rd,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
