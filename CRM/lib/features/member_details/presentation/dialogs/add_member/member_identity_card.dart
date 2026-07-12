import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/member_avatar.dart';

/// A compact member card — avatar + name + optional email — used in the
/// add-member flow's confirmation step.
class MemberIdentityCard extends StatelessWidget {
  final String name;
  final String? email;
  final String? photoUrl;

  const MemberIdentityCard({
    super.key,
    required this.name,
    this.email,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
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
            size: DesignConstants.rankBeltSmall,
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
        ],
      ),
    );
  }
}
