import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';

/// One selectable membership row in the cancel checklist —
/// plan name plus a status subtitle derived from the covered
/// member's scheduled exit. A row that is already cancelling
/// is shown for context but is not selectable.
class CancelMembershipRow extends StatelessWidget {
  final CancelTarget target;
  final bool selected;
  final VoidCallback onTap;

  const CancelMembershipRow({
    super.key,
    required this.target,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final exit = target.membership.exitDate;
    final alreadyCancelling =
        exit?.kind == MembershipExitKind.cancelling;
    final dateFmt = DateFormat('MMM d, yyyy');
    final String subtitle;
    final Color subtitleColor;
    if (alreadyCancelling) {
      subtitle = 'Already cancelling '
          '${dateFmt.format(exit!.date.toLocal())}';
      subtitleColor = DesignConstants.okYellow;
    } else if (exit != null) {
      subtitle =
          'Ends ${dateFmt.format(exit.date.toLocal())}';
      subtitleColor = DesignConstants.text2nd;
    } else {
      final until = target.membership.nextDueDate ??
          target.membership.startDate;
      subtitle =
          'Access until ${dateFmt.format(until.toLocal())}';
      subtitleColor = DesignConstants.text2nd;
    }
    return InkWell(
      onTap: alreadyCancelling ? null : onTap,
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
                  ? Symbols.radio_button_checked_sharp
                  : Symbols.radio_button_unchecked_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeLarge,
              color: selected
                  ? DesignConstants.badRed
                  : DesignConstants.text2nd,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    target.membership.planName,
                    style: DesignConstants.h3,
                  ),
                  Text(
                    subtitle,
                    style: DesignConstants.pSmall.copyWith(
                      color: subtitleColor,
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
