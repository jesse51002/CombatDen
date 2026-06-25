import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Confirms ending a ONE-TIME / TRIAL membership early. Dispatches
/// [EndMembershipRequested] (sets the end date to today → 'ended'). No
/// money moves — refunding is the separate refund action.
class EndMembershipDialog extends StatelessWidget {
  final MembershipInfo membership;
  final String coveredMemberId;
  final String coveredMemberName;

  const EndMembershipDialog({
    super.key,
    required this.membership,
    required this.coveredMemberId,
    required this.coveredMemberName,
  });

  static Future<void> show({
    required BuildContext context,
    required MembershipInfo membership,
    required String coveredMemberId,
    required String coveredMemberName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: EndMembershipDialog(
          membership: membership,
          coveredMemberId: coveredMemberId,
          coveredMemberName: coveredMemberName,
        ),
      ),
    );
  }

  void _submit(BuildContext context) {
    final itemId = membership.itemId;
    context.read<MemberDetailBloc>().add(
          EndMembershipRequested(
            itemId: itemId,
            memberId: coveredMemberId,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'End membership',
      body: Text(
        'End $coveredMemberName’s ${membership.planName} now? It will '
        'be marked ended and lose access. This does not refund any '
        'payment — use Refund for that.',
        style: DesignConstants.p.copyWith(color: DesignConstants.text),
      ),
      actions: AppDialogActions(
        primaryLabel: 'End membership',
        primaryColor: DesignConstants.badRed,
        primaryOnPressed: () => _submit(context),
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
