import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Confirms a cash payment for a specific membership's
/// current billing cycle. Dispatches
/// [MarkPaidCashRequested].
class MarkPaidCashDialog extends StatelessWidget {
  final String crmUserId;
  final MembershipInfo membership;

  const MarkPaidCashDialog({
    super.key,
    required this.crmUserId,
    required this.membership,
  });

  static Future<void> show({
    required BuildContext context,
    required String crmUserId,
    required MembershipInfo membership,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: MarkPaidCashDialog(
          crmUserId: crmUserId,
          membership: membership,
        ),
      ),
    );
  }

  Future<void> _onConfirm(BuildContext context) async {
    final itemId = membership.itemIdFor(crmUserId);
    if (itemId == null) return;

    final byId = <String, bool>{};
    final affected = <BillingAffectedPerson>[];
    for (final p in membership.payingFor) {
      if (byId.containsKey(p.crmUserId)) continue;
      byId[p.crmUserId] = true;
      affected.add(
        BillingAffectedPerson(
          fullName: p.fullName,
          initial:
              p.firstName.isNotEmpty ? p.firstName[0] : '?',
          photoUrl: p.photoUrl,
        ),
      );
    }

    final amount = formatMinorUnits(
      membership.totalPrice,
      currency: 'USD',
    );
    final confirmed =
        await BillingConfirmationDialog.show(
      context: context,
      title: 'Confirm cash payment',
      summary: 'Records a $amount cash payment for '
          '${membership.planName} and advances the billing '
          'cycle.',
      effects: [
        BillingEffect(
          icon: Symbols.payments_sharp,
          text: '$amount recorded as cash.',
        ),
        const BillingEffect(
          icon: Symbols.event_available_sharp,
          text: 'Billing cycle advances — no card charge.',
        ),
      ],
      affected: affected,
      confirmLabel: 'Mark Paid',
      confirmColor: DesignConstants.primaryColor,
    );
    if (!confirmed || !context.mounted) return;

    context.read<MemberDetailBloc>().add(
          MarkPaidCashRequested(
            itemId: itemId,
            crmUserId: crmUserId,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm =
        membership.itemIdFor(crmUserId) != null;
    return AppDialog(
      title: 'Mark Paid (Cash)',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            'Record a cash payment for '
            '${membership.planName}. This advances the '
            'billing cycle without running a card charge.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          _Row(
            label: 'Amount due',
            value: formatMinorUnits(
              membership.totalPrice,
              currency: 'USD',
            ),
          ),
          if (!canConfirm)
            Text(
              'This membership cannot be marked paid yet '
              '— the backend needs to expose its item id.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Review Payment',
        primaryColor: DesignConstants.primaryColor,
        primaryOnPressed:
            canConfirm ? () => _onConfirm(context) : null,
        secondaryLabel: 'Cancel',
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            label,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
        Text(
          value,
          style: DesignConstants.h3,
        ),
      ],
    );
  }
}
