import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';

/// Step 0 — pick which person the action applies to. Shown
/// only when the member has other selectable accounts.
///
/// [candidates] are the OTHER accounts (besides the viewed
/// [member], who is always listed first) the caller offers —
/// the charge dialog passes the member's authorized payers,
/// the start wizard the people the payer may pay for.
/// [disabledMemberIds] greys out (and blocks taps on)
/// participants the caller can't act on, mapping each member
/// id to a reason shown in place of the tile subtitle.
/// [title] / [subtitle] override the default copy.
/// [subtitleBuilder] supplies each tile's fixed role label
/// (e.g. "Authorized payer" / "Member getting Membership") —
/// it does not change with selection.
class StartMembershipParticipantStep extends StatelessWidget {
  final MemberDetailResponse member;

  /// The other selectable accounts (the viewed [member] is
  /// always listed first, ahead of these).
  final List<LinkedAccount> candidates;
  final String selectedMemberId;
  final ValueChanged<StartMembershipParticipant> onSelected;

  /// Member id → greyed-out reason for participants that
  /// should be shown but are not selectable.
  final Map<String, String> disabledMemberIds;

  final String? title;
  final String? subtitle;

  /// Which member id is the billable party. Defaults to
  /// the viewed [member]; the Start Memberships wizard
  /// overrides it when launched from a member whose payer is
  /// one of their authorized payers.
  final String? payerMemberId;

  /// Builds the fixed subtitle/role label for a tile. When
  /// null, tiles show only their name (plus any disabled
  /// reason). The label is constant — never selection-driven.
  final String Function(StartMembershipParticipant)?
      subtitleBuilder;

  /// Extra widgets rendered below the participant tiles, in the same
  /// medium-gap column — the caller's adder tiles (e.g. the payer step's
  /// "New member" / "Link someone"). Empty for callers with no adders.
  final List<Widget> trailing;

  const StartMembershipParticipantStep({
    super.key,
    required this.member,
    required this.candidates,
    required this.selectedMemberId,
    required this.onSelected,
    this.disabledMemberIds = const {},
    this.title,
    this.subtitle,
    this.payerMemberId,
    this.subtitleBuilder,
    this.trailing = const [],
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
      ...candidates.map(
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
                  'Pick the person this action applies to.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            ...participants.map((p) {
              final disabledReason = disabledMemberIds[p.memberId];
              return _ParticipantTile(
                participant: p,
                selected: p.memberId == selectedMemberId,
                subtitle: disabledReason ?? subtitleBuilder?.call(p),
                disabled: disabledReason != null,
                onTap: () => onSelected(p),
              );
            }),
            ...trailing,
          ],
        ),
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final StartMembershipParticipant participant;
  final bool selected;

  /// Fixed subtitle (role label or disabled reason); null
  /// renders the tile with just the name.
  final String? subtitle;
  final bool disabled;
  final VoidCallback onTap;

  const _ParticipantTile({
    required this.participant,
    required this.selected,
    required this.disabled,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
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
                if (subtitle != null)
                  Text(
                    subtitle!,
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
