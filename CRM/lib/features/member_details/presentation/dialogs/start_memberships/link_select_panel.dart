import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_direction.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_person_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_note.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_panel.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/paginated_member_picker.dart';

/// The search half of the link dialog: the roster, paged, plus the two facts
/// a search box cannot state about itself — that it loads as it scrolls, and
/// WHO can never appear in it.
///
/// It is skipped entirely when the dialog is opened for somebody already
/// named (a row picked off the run's own roster), which is the whole reason
/// it is a widget of its own rather than a branch inside the dialog's body.
class LinkSelectPanel extends StatelessWidget {
  final AuthorizeDirection direction;

  /// The fixed party of the authorization — who the list is filtered around.
  final String anchorName;

  final MemberPageFetcher fetchPage;
  final int pageSize;
  final String? selectedId;

  /// The waiver read that failed, said under the list it was started from.
  final String? error;

  final ValueChanged<MemberPickerEntry> onSelected;

  const LinkSelectPanel({
    super.key,
    required this.direction,
    required this.anchorName,
    required this.fetchPage,
    required this.pageSize,
    required this.selectedId,
    required this.error,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final failed = error;
    return TaskPanel(
      fill: true,
      children: [
        Expanded(
          child: PaginatedMemberPicker(
            fetchPage: fetchPage,
            pageSize: pageSize,
            selectedId: selectedId,
            expand: true,
            onSelected: onSelected,
          ),
        ),
        if (failed != null)
          Text(
            failed,
            style: DesignConstants.pSemibold.copyWith(
              color: DesignConstants.badRed,
            ),
          ),
        const TaskNote(
          StartPersonCopy.findPaging,
          textAlign: TextAlign.center,
        ),
        const Hairline(),
        TaskNote(
          StartPersonCopy.findNotListed(
            direction: direction,
            anchorName: anchorName,
          ),
        ),
      ],
    );
  }
}
