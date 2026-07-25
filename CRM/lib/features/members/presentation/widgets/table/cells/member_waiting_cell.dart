import 'package:flutter/material.dart';

import 'package:crm/features/members/presentation/widgets/table/_helpers.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/simple_text_cell.dart';

/// "Waiting" column cell for the Incomplete view — how long this
/// unfinished signup has been sitting in the queue ("Today", "1 day",
/// "12 days"), coloured by how stale it has gone.
class MemberWaitingCell extends StatelessWidget {
  final int daysWaiting;

  const MemberWaitingCell({
    super.key,
    required this.daysWaiting,
  });

  @override
  Widget build(BuildContext context) {
    return SimpleTextCell(
      text: waitingLabel(daysWaiting),
      color: waitingColor(daysWaiting),
    );
  }
}
