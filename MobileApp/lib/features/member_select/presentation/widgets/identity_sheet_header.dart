import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/gym_line.dart';
import 'package:mobile_app/shared/widgets/member_avatar.dart';

// Avatar scale for the sheet's current-member header (row scale, not the
// topbar's glyph scale).
const double _kAvatarDiameter = 48.0;

/// The identity sheet's answer to "who am I right now?": the current member's
/// avatar, name, gym, and the signed-in email.
///
/// The email is here because one verified email legitimately resolves to
/// SEVERAL member rows — the name alone answers "which profile", only the
/// email answers "which account".
class IdentitySheetHeader extends StatelessWidget {
  const IdentitySheetHeader({
    super.key,
    required this.fullName,
    required this.gymName,
    this.gymLogoUrl,
    this.photoUrl,
    this.firstName,
    this.lastName,
    this.email,
  });

  final String fullName;
  final String gymName;
  final String? gymLogoUrl;
  final String? photoUrl;
  final String? firstName;
  final String? lastName;
  final String? email;

  /// Name, else the signed-in email, else a neutral label — the header always
  /// has a title, even on an offline boot with no cached name.
  String get _title {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail;
    return 'Your profile';
  }

  @override
  Widget build(BuildContext context) {
    final mail = email?.trim();
    return Semantics(
      header: true,
      child: Row(
        spacing: DesignConstants.spacingLarge,
        children: [
          MemberAvatar(
            diameter: _kAvatarDiameter,
            photoUrl: photoUrl,
            firstName: firstName,
            lastName: lastName,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  _title,
                  style: DesignConstants.h1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (gymName.trim().isNotEmpty)
                  GymLine(gymName: gymName, gymLogoUrl: gymLogoUrl),
                if (mail != null && mail.isNotEmpty && mail != _title)
                  Text(
                    mail,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
