import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/data/mock_member_history.dart';
import 'package:crm/features/members/presentation/widgets/specific_member/profile_header/profile_action_buttons.dart';

/// Top of the SpecificMember card: name with status suffix, email with
/// copy affordance, and the row of three outlined action buttons.
class ProfileHeader extends StatelessWidget {
  final DemoMember member;

  const ProfileHeader({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingLarge,
      children: [
        _NameAndEmail(member: member),
        const ProfileActionButtons(),
      ],
    );
  }
}

class _NameAndEmail extends StatelessWidget {
  final DemoMember member;
  const _NameAndEmail({required this.member});

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          '${member.fullName} (${member.statusLabel})',
          style: DesignConstants.big2Bold,
          textAlign: TextAlign.center,
        ),
        _EmailRow(email: member.email),
      ],
    );
  }
}

class _EmailRow extends StatelessWidget {
  final String email;
  const _EmailRow({required this.email});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          email,
          style: DesignConstants.h2.copyWith(
            color: DesignConstants.hyperlink,
          ),
        ),
        InkWell(
          onTap: () => debugPrint('TODO: copy email "$email"'),
          child: Icon(
            Symbols.content_copy_sharp,
            size: DesignConstants.iconSizeMedium,
            color: DesignConstants.text2nd,
            weight: DesignConstants.iconWeight,
          ),
        ),
      ],
    );
  }
}
