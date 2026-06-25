import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/edit_membership_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The membership card's single action entry point: an "Edit membership"
/// button that opens [EditMembershipDialog] — a menu of the actions valid
/// for the shown membership's type and status (upgrade plan, migrate to
/// current price, cancel, freeze for recurring; end, refund for
/// one-time / trial). Disabled while the membership is mid-task or before
/// its row resolves.
class MembershipActionsRow extends StatelessWidget {
  final MemberDetailResponse member;

  /// The membership the carousel is currently showing — the one the
  /// edit menu acts on.
  final MembershipInfo? currentMembership;

  /// When true the membership's item is part of an in-progress task —
  /// editing is disabled.
  final bool isInTask;

  const MembershipActionsRow({
    super.key,
    required this.member,
    this.currentMembership,
    this.isInTask = false,
  });

  @override
  Widget build(BuildContext context) {
    final membership = currentMembership;
    return AppOutlineButton(
      fullWidth: true,
      text: 'Edit membership',
      borderRadius: DesignConstants.radiusSmall,
      onPressed: (isInTask || membership == null)
          ? null
          : () => EditMembershipDialog.show(
                context: context,
                member: member,
                membership: membership,
                coveredMemberId: member.memberId,
                coveredMemberName: member.fullName,
              ),
    );
  }
}
