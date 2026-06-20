import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/widgets/proration_selector.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Migrates a member's membership to the plan's current
/// active price. The merged contract takes no target price
/// id — only `item_id`, `member_id`, and a proration choice
/// — so this dialog only offers the proration choice and
/// dispatches [UpdatePriceRequested].
class UpdatePriceDialog extends StatefulWidget {
  final MembershipInfo membership;
  final String coveredMemberId;
  final String coveredMemberName;

  const UpdatePriceDialog({
    super.key,
    required this.membership,
    required this.coveredMemberId,
    required this.coveredMemberName,
  });

  /// Resolves the membership item for [coveredMemberId] and
  /// shows the dialog. No-op when the member is not covered.
  static Future<void> show({
    required BuildContext context,
    required MembershipInfo membership,
    required String coveredMemberId,
    required String coveredMemberName,
  }) {
    if (membership.itemIdFor(coveredMemberId) == null) {
      return Future.value();
    }
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: UpdatePriceDialog(
          membership: membership,
          coveredMemberId: coveredMemberId,
          coveredMemberName: coveredMemberName,
        ),
      ),
    );
  }

  @override
  State<UpdatePriceDialog> createState() =>
      _UpdatePriceDialogState();
}

class _UpdatePriceDialogState extends State<UpdatePriceDialog> {
  ProrationBehavior _prorationBehavior =
      ProrationBehavior.noCharge;

  void _submit() {
    final itemId =
        widget.membership.itemIdFor(widget.coveredMemberId);
    if (itemId == null) {
      Navigator.of(context).pop();
      return;
    }
    context.read<MemberDetailBloc>().add(
          UpdatePriceRequested(
            itemId: itemId,
            memberId: widget.coveredMemberId,
            prorationBehavior: _prorationBehavior,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Migrate to current price',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Move ${widget.coveredMemberName}’s '
            '${widget.membership.planName} membership to the '
            'plan’s current active price. They are currently '
            'billed at an older price.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
          ProrationSelector(
            value: _prorationBehavior,
            onChanged: (v) =>
                setState(() => _prorationBehavior = v),
          ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Migrate price',
        primaryOnPressed: _submit,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () =>
            Navigator.of(context).pop(),
      ),
    );
  }
}
