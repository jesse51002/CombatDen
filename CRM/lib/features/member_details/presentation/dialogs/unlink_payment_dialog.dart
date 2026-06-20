import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Confirms removing the saved card / payment method from
/// the account, then dispatches [UnlinkPaymentRequested].
class UnlinkPaymentDialog {
  UnlinkPaymentDialog._();

  static Future<void> show({
    required BuildContext context,
    required String memberName,
    String? cardLabel,
  }) async {
    final bloc = context.read<MemberDetailBloc>();
    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Remove card',
      summary:
          'Remove the saved card on $memberName’s account? '
          'It is deleted from the account entirely — there is '
          'no undo.',
      confirmLabel: 'Remove card',
      confirmColor: DesignConstants.badRed,
      effects: [
        BillingEffect(
          icon: Symbols.credit_card_off_sharp,
          text: cardLabel == null
              ? 'The saved card is removed from the account.'
              : '$cardLabel is removed from the account.',
        ),
        BillingEffect(
          icon: Symbols.payments_sharp,
          text: 'Until a new card is added, payments can '
              'only be taken in cash.',
        ),
      ],
      warning:
          'EVERY recurring membership on this account becomes '
          'unpayable by card until a new card is added — until '
          'then their bills can only be settled in cash.',
    );

    if (!confirmed) return;
    bloc.add(const UnlinkPaymentRequested());
  }
}
