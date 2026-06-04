import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/simple_text_cell.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// Membership status cell — plain text in the status's
/// color (no pill background).
///
/// [text] is the pre-formatted label from the backend
/// (e.g. "Monthly plan"). Falls back to the status's
/// [displayLabel] when no text is provided.
class MemberStatusCell extends StatelessWidget {
  final MembershipStatus status;
  final String? text;

  const MemberStatusCell({
    super.key,
    required this.status,
    this.text,
  });

  Color _fg() {
    return switch (status) {
      MembershipStatus.active => DesignConstants.goodGreen,
      MembershipStatus.trial => DesignConstants.primaryColor,
      MembershipStatus.overdue => DesignConstants.badRed,
      MembershipStatus.frozen => DesignConstants.okYellow,
      MembershipStatus.cancelled ||
      MembershipStatus.ended =>
        DesignConstants.badRed,
      _ => DesignConstants.text2nd,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SimpleTextCell(
      text: text ?? status.displayLabel,
      color: _fg(),
    );
  }
}
