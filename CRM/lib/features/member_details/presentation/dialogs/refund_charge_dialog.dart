import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Confirms a full refund of a prior [PaymentRecord], then
/// dispatches [RefundChargeRequested].
///
/// NOTE: the merged contract has no refund endpoint — the
/// repository targets an assumed path that will 404 until
/// the backend ships it (see `MemberRepository.refundCharge`).
/// The frozen [RefundChargeRequested] event exists, so the
/// seam is wired; the confirmation flags that the action may
/// not yet complete, and the bloc's [MemberActionError] path
/// surfaces a real failure.
class RefundChargeDialog {
  RefundChargeDialog._();

  static Future<void> show({
    required BuildContext context,
    required PaymentRecord charge,
  }) async {
    final bloc = context.read<MemberDetailBloc>();
    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Refund charge',
      summary:
          'Refund the '
          '${formatMinorUnits(charge.amount, currency: charge.currency)} '
          'charge from ${formatDay(charge.chargeTime)}?',
      confirmLabel: 'Refund',
      confirmColor: DesignConstants.badRed,
      effects: [
        BillingEffect(
          icon: Symbols.undo_sharp,
          text:
              '${formatMinorUnits(charge.amount, currency: charge.currency)} '
              'returned to the original payment method.',
        ),
      ],
      warning:
          'Refunds are not yet enabled on the backend, so '
          'this may not complete. You will see an error if '
          'it could not be processed.',
    );

    if (!confirmed) return;
    bloc.add(
      RefundChargeRequested(chargeId: charge.chargeId),
    );
  }
}
