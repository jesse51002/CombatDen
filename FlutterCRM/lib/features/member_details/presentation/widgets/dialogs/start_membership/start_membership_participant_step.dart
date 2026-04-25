import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/start_membership/start_membership_participant.dart';

/// Step 0 — pick which person at the linked-account family
/// the new membership will apply to. The primary member is
/// the billable party regardless; only the membership row's
/// `crm_user_id` changes.
class StartMembershipParticipantStep extends StatelessWidget {
  final MemberDetailResponse member;
  final String selectedCrmUserId;
  final ValueChanged<StartMembershipParticipant> onSelected;

  /// Map of `crmUserId` → reason string for participants
  /// that should be greyed out and un-tappable.
  final Map<String, String> disabledCrmUserIds;

  /// Customizes the subtitle copy shown under the step
  /// title. Defaults to the Start Membership phrasing.
  final String? title;
  final String? subtitle;

  const StartMembershipParticipantStep({
    super.key,
    required this.member,
    required this.selectedCrmUserId,
    required this.onSelected,
    this.disabledCrmUserIds = const {},
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final participants = <StartMembershipParticipant>[
      StartMembershipParticipant(
        crmUserId: member.crmUserId,
        name: member.fullName,
        photoUrl: member.photoUrl,
        isPayer: true,
      ),
      ...member.linkedAccounts.map(
        (LinkedAccount a) => StartMembershipParticipant(
          crmUserId: a.crmUserId,
          name: a.fullName,
          photoUrl: a.photoUrl,
          isPayer: false,
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          title ?? 'Who is this membership for?',
          style: DesignConstants.h3,
        ),
        Text(
          subtitle ??
              '${member.fullName} remains the billable '
                  'party — card charges still come off '
                  'their account.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: participants
              .map(
                (p) => _ParticipantTile(
                  participant: p,
                  selected:
                      p.crmUserId == selectedCrmUserId,
                  disabledReason:
                      disabledCrmUserIds[p.crmUserId],
                  onTap: () => onSelected(p),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final StartMembershipParticipant participant;
  final bool selected;
  final String? disabledReason;
  final VoidCallback onTap;

  const _ParticipantTile({
    required this.participant,
    required this.selected,
    required this.disabledReason,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = disabledReason != null;
    final content = Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: selected
            ? DesignConstants.primaryColor
                .withValues(alpha: 0.12)
            : DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: selected
              ? DesignConstants.primaryColor
              : DesignConstants.divider,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Avatar(participant: participant),
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
                  disabled
                      ? disabledReason!
                      : participant.isPayer
                          ? 'Account holder · pays the bill'
                          : 'Linked account · billed via '
                              'account holder',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            selected
                ? Symbols.radio_button_checked_sharp
                : Symbols.radio_button_unchecked_sharp,
            weight: DesignConstants.iconWeight,
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.text2nd,
          ),
        ],
      ),
    );
    if (disabled) {
      return Opacity(opacity: 0.4, child: content);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: content,
    );
  }
}

class _Avatar extends StatelessWidget {
  final StartMembershipParticipant participant;

  const _Avatar({required this.participant});

  @override
  Widget build(BuildContext context) {
    final initial = participant.name.isNotEmpty
        ? participant.name[0].toUpperCase()
        : '?';
    return CircleAvatar(
      radius: 18,
      backgroundColor: DesignConstants.card,
      backgroundImage: participant.photoUrl != null
          ? NetworkImage(participant.photoUrl!)
          : null,
      child: participant.photoUrl == null
          ? Text(
              initial,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text,
              ),
            )
          : null,
    );
  }
}
