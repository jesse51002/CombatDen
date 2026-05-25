import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// A member row in the right sidebar quick-list.
///
/// Displays the member's name. Tappable to navigate to that
/// member's detail page.
class MemberListItem extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;

  const MemberListItem({
    super.key,
    required this.name,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium
        ),
        child: Text(
          name,
          style: DesignConstants.p,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
