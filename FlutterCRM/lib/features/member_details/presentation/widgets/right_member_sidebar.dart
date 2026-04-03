import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/shared/widgets/member_list_item.dart';

/// Right sidebar showing a searchable list of all
/// members. Always visible.
class RightMemberSidebar extends StatelessWidget {
  final List<MemberSummary> members;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onMemberTap;

  const RightMemberSidebar({
    super.key,
    required this.members,
    required this.onSearchChanged,
    required this.onMemberTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200.0,
      color: DesignConstants.card,
      padding: EdgeInsets.fromLTRB(
        DesignConstants.paddingSmall, 
        DesignConstants.paddingBig,
        0, 0
      ),
      child: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.all(
              DesignConstants.spacingSmall,
            ),
            child: Semantics(
              label: 'Search members',
              child: TextField(
                onChanged: onSearchChanged,
                style: DesignConstants.h2,
                decoration: InputDecoration(
                  hintText: 'search...',
                  hintStyle:
                      DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                  prefixIcon: Icon(
                    Symbols.search_sharp,
                    color: DesignConstants.text3rd,
                    size: 18,
                    weight: DesignConstants.iconWeight,
                  ),
                  filled: true,
                  fillColor:
                      DesignConstants.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      DesignConstants.radiusSmall,
                    ),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(
                    horizontal:
                        DesignConstants.spacingSmall,
                    vertical:
                        DesignConstants.spacingSmall,
                  ),
                  isDense: true,
                ),
              ),
            ),
          ),
          // Member list
          Expanded(
            child: ListView.builder(
              itemCount: members.length,
              itemBuilder: (_, index) {
                final member = members[index];
                return MemberListItem(
                  name: member.fullName,
                  photoUrl: member.photoUrl,
                  onTap: () =>
                      onMemberTap(member.crmUserId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
