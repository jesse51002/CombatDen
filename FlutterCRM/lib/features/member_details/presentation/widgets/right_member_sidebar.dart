import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/member_list_item.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

/// Right sidebar showing a searchable, paginated list of
/// gym members. Always visible on desktop.
class RightMemberSidebar extends StatelessWidget {
  final String gymId;
  final ValueChanged<String> onMemberTap;

  const RightMemberSidebar({
    super.key,
    required this.gymId,
    required this.onMemberTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200.0,
      color: DesignConstants.card,
      padding: const EdgeInsets.fromLTRB(
        DesignConstants.paddingSmall,
        DesignConstants.paddingBig,
        DesignConstants.paddingSmall,
        0,
      ),
      child: PaginatedMemberPicker(
        gymId: gymId,
        expand: true,
        onSelected: (row) => onMemberTap(row.crmUserId),
        itemBuilder: (context, row, selected, onTap) =>
            MemberListItem(
          name: row.name,
          photoUrl: row.avatarUrl,
          onTap: onTap,
        ),
      ),
    );
  }
}
