import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/member_avatar.dart';

/// "Name" column cell — the member's full name with an avatar.
/// The avatar is the shared [MemberAvatar]: the photo, or the
/// member's initials on a soft accent fill when there is none.
class MemberNameCell extends StatelessWidget {
  final String name;
  final String? avatarUrl;

  const MemberNameCell({
    super.key,
    required this.name,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        MemberAvatar(
          name: name,
          photoUrl: avatarUrl,
          size: DesignConstants.iconSizeLarge,
        ),
        Flexible(
          child: Text(
            name,
            style: DesignConstants.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
