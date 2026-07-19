import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/group_member.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/payer_radio_tile.dart';

/// The choose-payer step: pick the one person who pays for the whole group and
/// signs an authorization for each of the others. Once a payer is picked a
/// helper line spells out how many authorizations they'll sign.
class ChoosePayerView extends StatelessWidget {
  final List<GroupMember> group;
  final String? selectedPayerId;
  final ValueChanged<String> onSelect;

  const ChoosePayerView({
    super.key,
    required this.group,
    required this.selectedPayerId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('Who pays for the group?', style: DesignConstants.h2),
        Text(
          'Pick one person. They pay for everyone here and sign an '
          'authorization for each of the others.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            for (final m in group)
              PayerRadioTile(
                name: m.fullName,
                photoUrl: m.photoUrl,
                wasExisting: m.wasExisting,
                selected: m.memberId == selectedPayerId,
                onTap: () => onSelect(m.memberId),
              ),
          ],
        ),
        if (selectedPayerId != null)
          _Helper(group: group, payerId: selectedPayerId!),
      ],
    );
  }
}

class _Helper extends StatelessWidget {
  final List<GroupMember> group;
  final String payerId;

  const _Helper({required this.group, required this.payerId});

  @override
  Widget build(BuildContext context) {
    final payer = group.firstWhere((m) => m.memberId == payerId);
    final first = payer.fullName.trim().split(RegExp(r'\s+')).first;
    final k = group.length - 1;
    final noun = k == 1 ? 'authorization' : 'authorizations';
    return Text(
      '$first will sign $k $noun, one for each other person.',
      style: DesignConstants.pSmall.copyWith(
        color: DesignConstants.text2nd,
      ),
    );
  }
}
