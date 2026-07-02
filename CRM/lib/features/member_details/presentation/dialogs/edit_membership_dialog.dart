import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_membership_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_one_time_membership_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/freeze/freeze_account_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/freeze/unfreeze_account_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/one_time_refund_flow.dart';
import 'package:crm/features/member_details/presentation/dialogs/update_price_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/upgrade_membership_dialog.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// One "Edit membership" entry point for a membership card — a menu of
/// the actions valid for THIS membership's type and status. Recurring:
/// upgrade plan, migrate to current price (if outdated), cancel, freeze.
/// One-time / trial: cancel membership, refund. Each item opens its own
/// sub-dialog stacked on this menu, then closes the menu.
class EditMembershipDialog extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;
  final String coveredMemberId;
  final String coveredMemberName;

  const EditMembershipDialog({
    super.key,
    required this.member,
    required this.membership,
    required this.coveredMemberId,
    required this.coveredMemberName,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
    required MembershipInfo membership,
    required String coveredMemberId,
    required String coveredMemberName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: EditMembershipDialog(
          member: member,
          membership: membership,
          coveredMemberId: coveredMemberId,
          coveredMemberName: coveredMemberName,
        ),
      ),
    );
  }

  bool get _isRecurring => membership.planType == PlanType.recurring.value;

  bool get _isOneTimeOrTrial =>
      membership.planType == PlanType.oneTime.value ||
      membership.planType == PlanType.trial.value;

  bool get _isTerminal => const {
        MembershipStatus.ended,
        MembershipStatus.cancelled,
      }.contains(membership.status);

  bool get _isOutdated =>
      membership.onOutdatedPrice &&
      membership.currentActivePrice != null;

  bool get _anyFrozen => member.memberships
      .any((m) => m.status == MembershipStatus.frozen);

  /// Opens [open] (a sub-dialog) stacked on this menu, then closes the
  /// menu once it returns. [context] still carries the bloc (re-provided
  /// at [show]), so the sub-dialog's own `context.read` resolves it.
  Future<void> _run(
    BuildContext context,
    Future<void> Function() open,
  ) async {
    await open();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Edit membership',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: _actions(context),
      ),
      actions: AppDialogActions(
        primaryLabel: 'Close',
        primaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final items = <Widget>[];
    if (_isRecurring) {
      if (!_isTerminal) {
        items.add(_button(
          'Upgrade plan',
          () => _run(
            context,
            () => UpgradeMembershipDialog.show(
              context: context,
              member: member,
              membership: membership,
              coveredMemberId: coveredMemberId,
            ),
          ),
        ));
      }
      if (_isOutdated && !_isTerminal) {
        items.add(_button(
          'Migrate to current price',
          () => _run(
            context,
            () => UpdatePriceDialog.show(
              context: context,
              membership: membership,
              memberId: coveredMemberId,
              coveredMemberName: coveredMemberName,
            ),
          ),
        ));
      }
      if (!_isTerminal) {
        items.add(_button(
          'Cancel membership',
          () => _run(
            context,
            () => CancelMembershipDialog.show(
              context: context,
              member: member,
              initialMembership: membership,
            ),
          ),
          destructive: true,
        ));
      }
      items.add(_button(
        _anyFrozen ? 'Unfreeze member' : 'Freeze member',
        () => _run(context, () => _freeze(context)),
      ));
    }
    if (_isOneTimeOrTrial) {
      if (!_isTerminal) {
        items.add(_button(
          'Cancel membership',
          () => _run(
            context,
            () => CancelOneTimeMembershipDialog.show(
              context: context,
              membership: membership,
              coveredMemberId: coveredMemberId,
              coveredMemberName: coveredMemberName,
            ),
          ),
          destructive: true,
        ));
      }
      items.add(_button(
        'Refund',
        () => _run(
          context,
          () => runOneTimeRefundFlow(
            context,
            member: member,
            membership: membership,
            coveredMemberId: coveredMemberId,
            coveredMemberName: coveredMemberName,
            allowEnd: !_isTerminal,
          ),
        ),
      ));
    }
    if (items.isEmpty) {
      items.add(Text(
        'No actions are available for this membership.',
        style: DesignConstants.pSmall
            .copyWith(color: DesignConstants.text2nd),
      ));
    }
    return items;
  }

  Future<void> _freeze(BuildContext context) async {
    if (_anyFrozen) {
      final bloc = context.read<MemberDetailBloc>();
      final confirmed = await UnfreezeAccountDialog.show(
        context: context,
        member: member,
      );
      if (confirmed) bloc.add(const UnfreezeAccountRequested());
      return;
    }
    await FreezeAccountDialog.show(context: context, member: member);
  }

  Widget _button(
    String label,
    VoidCallback onPressed, {
    bool destructive = false,
  }) {
    return AppOutlineButton(
      fullWidth: true,
      text: label,
      borderRadius: DesignConstants.radiusSmall,
      borderColor: destructive ? DesignConstants.badRed : null,
      textColor: destructive ? DesignConstants.badRed : null,
      onPressed: onPressed,
    );
  }
}
