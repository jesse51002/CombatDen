import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/cancel_membership/cancel_membership_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/freeze/freeze_account_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/freeze/unfreeze_account_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Row with Freeze/Unfreeze Account and Cancel Membership
/// buttons. The freeze label flips when any membership is
/// currently frozen.
class MembershipActionsRow extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo? currentMembership;

  const MembershipActionsRow({
    super.key,
    required this.member,
    this.currentMembership,
  });

  bool get _anyFrozen => member.memberships.any(
        (m) => m.status == MembershipStatus.frozen,
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingLarge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          _actionButton(
            _anyFrozen
                ? 'Unfreeze Account'
                : 'Freeze Account',
            onPressed: () => _onFreezeTap(context),
          ),
          _actionButton(
            'Cancel Membership',
            onPressed: member.memberships.isEmpty
                ? null
                : () => CancelMembershipDialog.show(
                      context: context,
                      member: member,
                      initialMembership:
                          currentMembership,
                    ),
          ),
        ],
      ),
    );
  }

  Future<void> _onFreezeTap(BuildContext context) async {
    if (_anyFrozen) {
      final confirmed = await UnfreezeAccountDialog.show(
        context: context,
        member: member,
      );
      if (confirmed && context.mounted) {
        context
            .read<MemberDetailBloc>()
            .add(const UnfreezeAccountRequested());
      }
      return;
    }
    await FreezeAccountDialog.show(
      context: context,
      member: member,
    );
  }

  Widget _actionButton(
    String label, {
    VoidCallback? onPressed,
  }) {
    return AppOutlineButton(
      text: label,
      onPressed: onPressed,
      fullWidth: true,
      borderRadius: DesignConstants.radiusSmall,
      textStyle: DesignConstants.h3,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingLarge,
        vertical: DesignConstants.spacingSmall,
      ),
    );
  }
}
