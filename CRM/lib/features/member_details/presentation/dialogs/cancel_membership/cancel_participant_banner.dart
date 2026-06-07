import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';

/// Compact banner shown on the membership-checklist step
/// reminding staff which person they're cancelling for once
/// they've moved past participant selection. Red-tinted to
/// signal the destructive flow.
class CancelParticipantBanner extends StatelessWidget {
  final StartMembershipParticipant participant;

  const CancelParticipantBanner({
    super.key,
    required this.participant,
  });

  @override
  Widget build(BuildContext context) {
    final initial = participant.name.isNotEmpty
        ? participant.name[0].toUpperCase()
        : '?';
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.badRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: DesignConstants.card,
            backgroundImage: participant.photoUrl != null
                ? NetworkImage(participant.photoUrl!)
                : null,
            child: participant.photoUrl == null
                ? Text(
                    initial,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
                children: [
                  const TextSpan(text: 'Cancelling for '),
                  TextSpan(
                    text: participant.name,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: participant.isPayer
                        ? ''
                        : ' (linked account)',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
