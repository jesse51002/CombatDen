import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/member_select/presentation/widgets/identity_sheet.dart';
import 'package:mobile_app/shared/widgets/member_avatar.dart';

/// The topbar's **identity control**: the member's avatar at glyph scale,
/// sitting in the trailing flank opposite the back chevron.
///
/// The topbar's grammar is a centred brand block between single-glyph
/// controls, so identity is a glyph too — an avatar is the learned tap target
/// for "my account", and it carries NO chevron because the avatar itself is
/// the affordance. Tapping opens the one surface that answers who you are,
/// which other profiles this email holds, and how to sign out.
///
/// It renders even with no name or photo (falling back to the person glyph):
/// sign-out lives behind it, so it can never disappear.
class TopbarIdentityAvatar extends StatelessWidget {
  const TopbarIdentityAvatar({
    super.key,
    required this.gymName,
    this.memberName,
    this.photoUrl,
    this.firstName,
    this.lastName,
  });

  final String gymName;
  final String? memberName;
  final String? photoUrl;
  final String? firstName;
  final String? lastName;

  @override
  Widget build(BuildContext context) {
    final name = memberName?.trim();
    final hasName = name != null && name.isNotEmpty;
    return Semantics(
      button: true,
      label: hasName
          ? 'Your profile. $name at $gymName. Switch profile or sign out'
          : 'Your profile. Switch profile or sign out',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => IdentitySheet.show(context),
        // The 8pt inset lifts the 32pt avatar to a 48pt target, matching the
        // back chevron's padding on the leading edge.
        child: Padding(
          padding: EdgeInsets.all(DesignConstants.spacingMedium),
          child: ExcludeSemantics(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: DesignConstants.divider,
                  width: DesignConstants.dividerThickness,
                ),
              ),
              child: ClipOval(
                child: MemberAvatar(
                  diameter: DesignConstants.iconSizeXl,
                  photoUrl: photoUrl,
                  firstName: firstName,
                  lastName: lastName,
                  initialsStyle: DesignConstants.h3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
