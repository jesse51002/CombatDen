import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';

/// Step 0 — pick which person the action applies to. The
/// primary member stays the billable party regardless; only
/// the membership row's owner changes. Shown only when the
/// member has linked accounts.
///
/// Reused by both the Start Membership and Cancel Membership
/// flows. [disabledMemberIds] greys out (and blocks taps on)
/// participants the caller can't act on, mapping each member
/// id to a reason shown in place of the tile subtitle.
/// [title] / [subtitle] override the default Start Membership
/// copy for other flows.
class StartMembershipParticipantStep extends StatelessWidget {
  final MemberDetailResponse member;
  final String selectedMemberId;
  final ValueChanged<StartMembershipParticipant> onSelected;

  /// Member id → greyed-out reason for participants that
  /// should be shown but are not selectable.
  final Map<String, String> disabledMemberIds;

  final String? title;
  final String? subtitle;

  /// Which member id is the billable party. Defaults to
  /// the viewed [member]; the Start Memberships wizard
  /// overrides it when launched from a linked child's page
  /// (the payer is then in `linkedAccounts`).
  final String? payerMemberId;

  const StartMembershipParticipantStep({
    super.key,
    required this.member,
    required this.selectedMemberId,
    required this.onSelected,
    this.disabledMemberIds = const {},
    this.title,
    this.subtitle,
    this.payerMemberId,
  });

  @override
  Widget build(BuildContext context) {
    final payerId = payerMemberId ?? member.memberId;
    final participants = <StartMembershipParticipant>[
      StartMembershipParticipant(
        memberId: member.memberId,
        name: member.fullName,
        photoUrl: member.photoUrl,
        isPayer: member.memberId == payerId,
      ),
      ...member.linkedAccounts.map(
        (LinkedAccount a) => StartMembershipParticipant(
          memberId: a.memberId,
          name: a.fullName,
          photoUrl: a.photoUrl,
          isPayer: a.memberId == payerId,
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              title ?? 'Who is this membership for?',
              style: DesignConstants.h2,
            ),
            Text(
              subtitle ??
                  '${member.fullName} remains the billable party — '
                      'card charges still come off their account.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: participants
              .map(
                (p) => _ParticipantTile(
                  participant: p,
                  selected: p.memberId == selectedMemberId,
                  disabledReason: disabledMemberIds[p.memberId],
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
    required this.onTap,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = disabledReason != null;
    final content = Container(
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
                  disabledReason ??
                      (participant.isPayer
                          ? 'Account holder · pays the bill'
                          : 'Linked account · billed via '
                              'account holder'),
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
            size: DesignConstants.iconSizeLarge,
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
