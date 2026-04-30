import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// A member row in the right sidebar quick-list.
///
/// Displays a small avatar and name. Tappable to
/// navigate to that member's detail page.
class MemberListItem extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final String? avatarAsset;
  final VoidCallback? onTap;

  const MemberListItem({
    super.key,
    required this.name,
    this.photoUrl,
    this.avatarAsset,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ImageProvider? bgImage = avatarAsset != null
        ? AssetImage(avatarAsset!)
        : (photoUrl != null ? NetworkImage(photoUrl!) : null);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium
        ),
        child: Row(
          spacing: DesignConstants.paddingSmall,
          children: [
            CircleAvatar(
              radius: 36.0 / 2,
              backgroundColor: DesignConstants.backgroundColor,
              backgroundImage: bgImage,
              child: bgImage == null
                  ? Icon(
                      Symbols.person_sharp,
                      size: 36.0 / 2,
                      color: DesignConstants.text3rd,
                      weight: DesignConstants.iconWeight,
                    )
                  : null,
            ),
            Expanded(
              child: Text(
                name,
                style: DesignConstants.p,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
