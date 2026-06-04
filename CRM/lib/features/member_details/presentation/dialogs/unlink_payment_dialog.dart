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
      title: 'Remove payment method',
      summary:
          'Remove the payment method on '
          '$memberName’s account?',
      confirmLabel: 'Remove card',
      confirmColor: DesignConstants.badRed,
      effects: [
        BillingEffect(
          icon: Symbols.credit_card_off_sharp,
          text: cardLabel == null
              ? 'The saved card will be detached.'
              : '$cardLabel will be detached.',
        ),
      ],
      warning:
          'Recurring memberships cannot be charged until '
          'a new card is added.',
    );

    if (!confirmed) return;
    bloc.add(const UnlinkPaymentRequested());
  }
}
