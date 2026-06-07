import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';

/// Compact banner shown on the plan/discount/review steps
/// reminding staff which person the membership is for once
/// they've moved past participant selection.
class StartMembershipParticipantBanner
    extends StatelessWidget {
  final StartMembershipParticipant participant;

  const StartMembershipParticipantBanner({
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
        color: DesignConstants.primaryColor10,
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
                  const TextSpan(text: 'Membership for '),
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
