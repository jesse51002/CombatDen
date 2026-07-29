import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/shared/widgets/gym_line.dart';
import 'package:mobile_app/shared/widgets/member_avatar.dart';

const double _kAvatarDiameter = 48.0;

/// One tappable row in the "Who's training?" picker: the member's avatar in a
/// circle (their photo, or their initials), their name, the gym (its logo +
/// name), and a trailing chevron. The avatar is the member — not the gym — so
/// two profiles on the same shared email (a family) stay distinguishable at a
/// glance; the gym line disambiguates the rows that differ only by gym.
///
/// Also the switch row inside the identity sheet, so the picker screen and the
/// sheet present a profile identically.
class MemberRow extends StatelessWidget {
  const MemberRow({
    super.key,
    required this.member,
    required this.onTap,
  });

  final MemberIdentity member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${member.fullName}, ${member.gymName}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _row(),
      ),
    );
  }

  Widget _row() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingSmall),
        child: Row(
          spacing: DesignConstants.spacingLarge,
          children: [
            MemberAvatar(
              diameter: _kAvatarDiameter,
              photoUrl: member.photoUrl,
              firstName: member.firstName,
              lastName: member.lastName,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    member.fullName,
                    style: DesignConstants.h2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  GymLine(
                    gymName: member.gymName,
                    gymLogoUrl: member.gymLogoUrl,
                  ),
                ],
              ),
            ),
            Icon(
              Symbols.chevron_right_sharp,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text3rd,
              size: DesignConstants.iconSizeLg,
            ),
          ],
        ),
      ),
    );
  }
}
