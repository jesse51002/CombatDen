import 'package:flutter/material.dart';

import 'package:crm/shared/widgets/member_row_tile.dart';

/// One checkbox row in the batch check-in multi-select roster — delegates
/// its body to the shared [MemberRowTile] so a member's row looks the same
/// here as in the attendee roster; trailing carries the selection
/// [Checkbox] and the whole row is tappable to toggle [selected].
class BatchCheckInMemberTile extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool selected;
  final VoidCallback onTap;

  const BatchCheckInMemberTile({
    super.key,
    required this.name,
    this.avatarUrl,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MemberRowTile(
      name: name,
      avatarUrl: avatarUrl,
      onTap: onTap,
      trailing: Checkbox(value: selected, onChanged: (_) => onTap()),
    );
  }
}
