import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/member_avatar.dart';

/// A compact member identity card — avatar + name + optional email in a
/// bordered surface. The shared primitive behind the add-member flow's
/// roster rows, confirmation card, duplicate-match cards, and payer tiles.
///
/// Defaults render the plain card+divider surface with a [rankBeltSmall]
/// avatar. Pass [trailing] for a badge/pill/radio, [avatarSize] for a
/// larger avatar, or [decoration] to override the surface (e.g. a selected
/// border). Selectable callers wrap this in their own `InkWell`.
class MemberIdentityCard extends StatelessWidget {
  final String name;
  final String? email;
  final String? photoUrl;
  final double avatarSize;
  final Widget? trailing;
  final BoxDecoration? decoration;

  const MemberIdentityCard({
    super.key,
    required this.name,
    this.email,
    this.photoUrl,
    this.avatarSize = DesignConstants.rankBeltSmall,
    this.trailing,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: decoration ??
          BoxDecoration(
            color: DesignConstants.card,
            borderRadius:
                BorderRadius.circular(DesignConstants.radiusSmall),
            border: Border.all(color: DesignConstants.divider),
          ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          MemberAvatar(
            name: name,
            photoUrl: photoUrl,
            size: avatarSize,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(name, style: DesignConstants.h3),
                if (email != null && email!.isNotEmpty)
                  Text(
                    email!,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
