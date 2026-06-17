import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_membership_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/freeze/freeze_account_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/freeze/unfreeze_account_dialog.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Account-level actions for the membership carousel:
/// Freeze / Unfreeze (label flips when any membership is
/// frozen) and Cancel membership (opens the two-step cancel
/// wizard, which resolves who and what to cancel itself).
class MembershipActionsRow extends StatelessWidget {
  final MemberDetailResponse member;

  /// The membership the carousel is currently showing — used
  /// only to seed the cancel wizard's default participant.
  final MembershipInfo? currentMembership;

  /// When true the membership's item is part of an in-progress
  /// upgrade task — all mutation actions are disabled.
  final bool isInTask;

  const MembershipActionsRow({
    super.key,
    required this.member,
    this.currentMembership,
    this.isInTask = false,
  });

  bool get _anyFrozen => member.memberships.any(
        (m) => m.status == MembershipStatus.frozen,
      );

  /// Whether the member has any recurring membership the
  /// cancel wizard could act on. The wizard owns the
  /// per-person / per-membership eligibility; this only gates
  /// whether the button is live at all.
  bool get _hasCancellable => member.memberships.any(
        (m) =>
            m.planType == 'recurring' &&
            m.members.isNotEmpty &&
            const {
              MembershipStatus.active,
              MembershipStatus.trial,
              MembershipStatus.frozen,
              MembershipStatus.overdue,
            }.contains(m.status),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        AppOutlineButton(
          fullWidth: true,
          text: _anyFrozen
              ? 'Unfreeze account'
              : 'Freeze account',
          borderRadius: DesignConstants.radiusSmall,
          onPressed: isInTask ? null : () => _onFreezeTap(context),
        ),
        AppOutlineButton(
          fullWidth: true,
          text: 'Cancel membership',
          borderColor: DesignConstants.badRed,
          textColor: DesignConstants.badRed,
          borderRadius: DesignConstants.radiusSmall,
          onPressed: (!isInTask && _hasCancellable)
              ? () => CancelMembershipDialog.show(
                    context: context,
                    member: member,
                    initialMembership: currentMembership,
                  )
              : null,
        ),
      ],
    );
  }

  Future<void> _onFreezeTap(BuildContext context) async {
    if (_anyFrozen) {
      final bloc = context.read<MemberDetailBloc>();
      final confirmed = await UnfreezeAccountDialog.show(
        context: context,
        member: member,
      );
      if (confirmed) {
        bloc.add(const UnfreezeAccountRequested());
      }
      return;
    }
    await FreezeAccountDialog.show(
      context: context,
      member: member,
    );
  }
}
