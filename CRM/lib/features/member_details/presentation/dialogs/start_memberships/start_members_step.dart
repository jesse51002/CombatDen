import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Step 2 — who's getting memberships. Multi-select over
/// the payer + members already linked to the payer (the
/// backend hard-rejects unlinked members: the start op
/// never links). The "link a member first" affordance jumps
/// to the existing link flow and returns here.
class StartMembersStep extends StatelessWidget {
  /// The PAYER's member detail (its `linkedAccounts` are
  /// the linkable family). Null while it is still loading.
  final MemberDetailResponse? payerDetail;
  final StartMembershipParticipant payer;
  final Set<String> selectedMemberIds;
  final ValueChanged<String> onToggle;
  final VoidCallback onLinkFirst;

  const StartMembersStep({
    super.key,
    required this.payerDetail,
    required this.payer,
    required this.selectedMemberIds,
    required this.onToggle,
    required this.onLinkFirst,
  });

  @override
  Widget build(BuildContext context) {
    final detail = payerDetail;
    if (detail == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: AppSpinner()),
      );
    }
    final candidates = <StartMembershipParticipant>[
      payer,
      ...detail.linkedAccounts.map(
        (a) => StartMembershipParticipant(
          memberId: a.memberId,
          name: a.fullName,
          photoUrl: a.photoUrl,
          isPayer: false,
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
              'Who is getting memberships?',
              style: DesignConstants.h2,
            ),
            Text(
              'Pick everyone to enroll in this run — '
              'the payer themselves and members already '
              'linked to them.',
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
            ...candidates.map(
              (c) => _MemberCheckTile(
                participant: c,
                selected: selectedMemberIds
                    .contains(c.memberId),
                onTap: () => onToggle(c.memberId),
              ),
            ),
            _LinkFirstTile(onTap: onLinkFirst),
          ],
        ),
      ],
    );
  }
}

class _MemberCheckTile extends StatelessWidget {
  final StartMembershipParticipant participant;
  final bool selected;
  final VoidCallback onTap;

  const _MemberCheckTile({
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

/// "Someone missing?" — unlinked members can't receive a
/// membership in this run; staff link them first via the
/// existing link flow, then return here.
class _LinkFirstTile extends StatelessWidget {
  final VoidCallback onTap;

  const _LinkFirstTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
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
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: DesignConstants.divider,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              Symbols.person_add_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.text2nd,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    'Someone missing? Link them first',
                    style: DesignConstants.p.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Unlinked members can’t be enrolled '
                    'here — starting never links.',
                    style: DesignConstants.pSmall
                        .copyWith(
                      color: DesignConstants.text2nd,
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
