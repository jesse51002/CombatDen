import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Confirms marking an open invoice as paid in cash (out of band), then
/// dispatches [MarkPaidCashRequested] for the resolved membership item.
///
/// TODO(C-078): if the open invoice is a consolidated family invoice (multiple
/// co-billed members), warn that cash-settling forgives the WHOLE invoice, not
/// just this member's line. Needs the invoice's paid_for span surfaced here.
class MarkPaidCashDialog {
  MarkPaidCashDialog._();

  static Future<void> show({
    required BuildContext context,
    required int amount,
    required String currency,
    required String itemId,
    required String coveredMemberId,
    required String payerName,
  }) async {
    final bloc = context.read<MemberDetailBloc>();
    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Mark paid in cash',
      summary:
          'Record $payerName’s invoice as paid in cash for '
          'this cycle?',
      confirmLabel: 'Mark paid',
      effects: [
        BillingEffect(
          icon: Symbols.attach_money_sharp,
          text:
              '${formatMinorUnits(amount, currency: currency)} '
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
