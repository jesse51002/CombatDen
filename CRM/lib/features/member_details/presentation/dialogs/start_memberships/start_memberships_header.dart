import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';

/// The wizard's persistent context header: who is PAYING
/// and — on the per-member configuration steps — which
/// MEMBER is currently being configured. Shown on every
/// screen past the payer pick so staff never wonder whose
/// card is charged or whose membership they're editing.
class StartMembershipsHeader extends StatelessWidget {
  final StartMembershipParticipant payer;

  /// The member currently being configured (plans /
  /// discounts steps). Null on the shared steps.
  final StartMembershipParticipant? currentMember;

  const StartMembershipsHeader({
    super.key,
    required this.payer,
    this.currentMember,
  });

  @override
  Widget build(BuildContext context) {
    final member = currentMember;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingSmall,
        children: [
          _HeaderLine(
            label: 'Paying',
            name: payer.name,
            photoUrl: payer.photoUrl,
          ),
          if (member != null)
            _HeaderLine(
              label: 'Configuring',
              name: member.name,
              photoUrl: member.photoUrl,
              suffix: member.memberId == payer.memberId
                  ? ' (the payer)'
                  : null,
            ),
        ],
      ),
    );
  }
}

class _HeaderLine extends StatelessWidget {
  final String label;
  final String name;
  final String? photoUrl;
  final String? suffix;

  const _HeaderLine({
    required this.label,
    required this.name,
    required this.photoUrl,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final initial =
        name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Row(
      spacing: DesignConstants.spacingMedium,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: DesignConstants.card,
          backgroundImage: photoUrl != null
              ? NetworkImage(photoUrl!)
              : null,
          child: photoUrl == null
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
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              children: [
                TextSpan(text: '$label: '),
                TextSpan(
                  text: name,
                  style:
                      DesignConstants.pSemibold.copyWith(
                    color: DesignConstants.text,
                  ),
                ),
                if (suffix != null)
                  TextSpan(text: suffix),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
