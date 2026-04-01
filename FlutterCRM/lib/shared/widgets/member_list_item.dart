import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A member row in the right sidebar quick-list.
///
/// Displays a small avatar and name. Tappable to
/// navigate to that member's detail page.
class MemberListItem extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final VoidCallback? onTap;

  const MemberListItem({
    super.key,
    required this.name,
    this.photoUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical:
              DesignConstants.spacingTiny,
          horizontal:
              DesignConstants.spacingSmall,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 36.0 / 2,
              backgroundColor: DesignConstants.backgroundColor,
              backgroundImage: photoUrl != null
                  ? NetworkImage(photoUrl!)
                  : null,
              child: photoUrl == null
                  ? Icon(
                      Icons.person,
                      size: 36.0 / 2,
                      color: DesignConstants.text3rd,
                    )
                  : null,
            ),
            const SizedBox(
              width:
                  DesignConstants.spacingSmall,
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
