import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Confirms marking the current cycle of a membership as
/// paid in cash (out of band), then dispatches
/// [MarkPaidCashRequested] for the resolved item.
class MarkPaidCashDialog {
  MarkPaidCashDialog._();

  static Future<void> show({
    required BuildContext context,
    required MembershipInfo membership,
    required String coveredMemberId,
    required String coveredMemberName,
  }) async {
    final itemId = membership.itemIdFor(coveredMemberId);
    if (itemId == null) return;

    final bloc = context.read<MemberDetailBloc>();
    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Mark paid in cash',
      summary:
          'Record $coveredMemberName’s '
          '${membership.planName} as paid in cash for '
          'this cycle?',
      confirmLabel: 'Mark paid',
      effects: [
        BillingEffect(
          icon: Symbols.attach_money_sharp,
          text:
              '${formatMinorUnits(membership.totalPrice)} '
              'recorded as a cash payment.',
        ),
        const BillingEffect(
          icon: Symbols.credit_card_off_sharp,
          text: 'The card on file will not be charged.',
        ),
      ],
    );

    if (!confirmed) return;
    bloc.add(
      MarkPaidCashRequested(
        itemId: itemId,
        memberId: coveredMemberId,
      ),
    );
  }
}
