import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/group_member.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/group_roster_row.dart';
import 'package:crm/shared/widgets/dashed_add_tile.dart';

/// The add-member flow's create-phase hub: a count-adaptive header, the
/// running group roster, and an "Add another person" adder. One person reads
/// as a confirmation; two or more reads as a group being assembled before a
/// payer is chosen.
class AddMemberRosterView extends StatelessWidget {
  final List<GroupMember> group;
  final VoidCallback onAddAnother;

  const AddMemberRosterView({
    super.key,
    required this.group,
    required this.onAddAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        _Header(group: group),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            for (var i = 0; i < group.length; i++)
              GroupRosterRow(
                name: group[i].fullName,
                email: group[i].email,
                photoUrl: group[i].photoUrl,
                wasExisting: group[i].wasExisting,
                isLast: i == group.length - 1,
                invite: group[i].invite,
              ),
          ],
        ),
        DashedAddTile(
          title: 'Add another person',
          subtitle: "They join this group. You'll choose who pays "
              'at the end.',
          onTap: onAddAnother,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final List<GroupMember> group;

  const _Header({required this.group});

  @override
  Widget build(BuildContext context) {
    if (group.length >= 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            '${group.length} people in this group',
            style: DesignConstants.h1,
            textAlign: TextAlign.center,
          ),
          Text(
            'Everyone in this group is paid for by one person. Add '
            'everyone first, then choose who pays. That person signs '
            'an authorization for each of the others.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    final only = group.isNotEmpty ? group.first : null;
    final name = only?.fullName ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Icon(
          Symbols.check_circle_sharp,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.goodGreen,
        ),
        Text(
          (only?.wasExisting ?? false)
              ? '$name is already a member'
              : '$name has been added',
          style: DesignConstants.h1,
          textAlign: TextAlign.center,
        ),
        // What actually happened to their app invite, in the backend's own
        // words — never an unqualified "invited" for a send that was held,
        // suppressed, or never asked for.
        if (only != null && only.invite.confirmation != null)
          Text(
            only.invite.confirmation!,
            style: DesignConstants.p.copyWith(
              color: only.invite.wasSent
                  ? DesignConstants.goodGreen
                  : DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
        Text(
          'Set up their membership now, or finish here. You can also '
          'add more people who are all paid for by one person.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
