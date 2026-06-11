import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';

/// One multi-select row in the members step: avatar, name,
/// payer/linked subtitle and the selection checkbox.
class StartMemberCheckTile extends StatelessWidget {
  final StartMembershipParticipant participant;
  final bool selected;
  final VoidCallback onTap;

  const StartMemberCheckTile({
    super.key,
    required this.participant,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = participant.name.isNotEmpty
        ? participant.name[0].toUpperCase()
        : '?';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          DesignConstants.paddingSmall,
        ),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor10
              : DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: DesignConstants.card,
              backgroundImage:
                  participant.photoUrl != null
                      ? NetworkImage(
                          participant.photoUrl!,
                        )
                      : null,
              child: participant.photoUrl == null
                  ? Text(
                      initial,
                      style:
                          DesignConstants.p.copyWith(
                        color: DesignConstants.text,
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    participant.name,
                    style: DesignConstants.h3,
                  ),
                  Text(
                    participant.isPayer
                        ? 'The payer'
                        : 'Linked to the payer',
                    style: DesignConstants.pSmall
                        .copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Symbols.check_box_sharp
                  : Symbols
                      .check_box_outline_blank_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeLarge,
              color: selected
                  ? DesignConstants.primaryColor
                  : DesignConstants.text2nd,
            ),
          ],
        ),
      ),
    );
  }
}
