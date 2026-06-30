import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// One member row: a photo-or-initials avatar + name, with an optional
/// [trailing] action slot (a selection [Checkbox], a remove button, …) and
/// an optional [onTap] making the whole row tappable.
///
/// Pure presentational — the single normalized shape shared by the
/// attendee roster (view) and the "Update attendees" picker (pick), so a
/// member looks identical whether you're viewing or selecting them.
/// Delegates the avatar to [InstructorAvatar] (photo-or-initials) rather
/// than hand-rolling either.
class MemberRowTile extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final Widget? trailing;
  final VoidCallback? onTap;

  const MemberRowTile({
    super.key,
    required this.name,
    this.avatarUrl,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingSmall,
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          InstructorAvatar(photoUrl: avatarUrl, name: name, diameter: 28),
          Expanded(
            child: Text(
              name,
              style: DesignConstants.p,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );

    if (onTap == null) return row;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: row,
    );
  }
}
