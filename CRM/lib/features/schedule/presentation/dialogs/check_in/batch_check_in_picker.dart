import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/batch_check_in_member_tile.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

/// Select body for a class-occurrence member batch: a searchable, paginated
/// multi-select roster (checkbox tiles driven by the parent's [selectedIds]).
/// Owns its own gym-scoped member-list page source; the parent owns the
/// [Set] of picked ids. Shared by the batch staff check-in ("Update
/// attendees") and the "Reserve members" dialog — [description] carries each
/// caller's own copy (the two flows read differently: "attended" vs. "to
/// reserve a spot").
class BatchCheckInPicker extends StatefulWidget {
  final String gymId;
  final String description;
  final Set<String> selectedIds;
  final String? inlineError;
  final ValueChanged<MemberPickerEntry> onToggle;

  const BatchCheckInPicker({
    super.key,
    required this.gymId,
    required this.description,
    required this.selectedIds,
    required this.onToggle,
    this.inlineError,
  });

  @override
  State<BatchCheckInPicker> createState() => _BatchCheckInPickerState();
}

class _BatchCheckInPickerState extends State<BatchCheckInPicker> {
  static const _pageSize = 20;
  final MembersListRepository _members =
      MembersListRepository(apiClient: ApiClient());

  Future<List<MemberPickerEntry>> _fetchPage(
    String query,
    int startIndex,
  ) async {
    final page = await _members.getMembersList(
      CrmMembersListRequest(
        gymId: widget.gymId,
        view: MembersListView.all,
        filters: MembersListFilters(name: query.isEmpty ? null : query),
        startIndex: startIndex,
        count: _pageSize,
      ),
    );
    return page.data
        .map(
          (r) => MemberPickerEntry(
            id: r.memberId,
            name: r.name,
            avatarUrl: r.avatarUrl,
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          widget.description,
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        SizedBox(
          height: DesignConstants.dialogMemberPickerHeight,
          child: PaginatedMemberPicker(
            fetchPage: _fetchPage,
            pageSize: _pageSize,
            expand: true,
            onSelected: widget.onToggle,
            itemBuilder: (context, entry, _, onTap) => BatchCheckInMemberTile(
              name: entry.name,
              avatarUrl: entry.avatarUrl,
              selected: widget.selectedIds.contains(entry.id),
              onTap: onTap,
            ),
          ),
        ),
        if (widget.inlineError != null)
          ErrorMessage(message: widget.inlineError!),
      ],
    );
  }
}
