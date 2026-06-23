import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Confirms removing [payerName] as an authorized payer for the
/// payee, then dispatches [UnlinkParentRequested].
///
/// De-authorization is authorization-layer only: it revokes the
/// "may pay" permission for future memberships. Memberships the
/// payer already funds keep their billing (the signature audit row
/// is also kept).
class UnlinkParentDialog {
  UnlinkParentDialog._();

  static Future<void> show({
    required BuildContext context,
    required String payeeMemberId,
    required String payerMemberId,
    required String payerName,
  }) async {
    final bloc = context.read<MemberDetailBloc>();
    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Remove authorized payer',
      summary:
          'Remove $payerName as an authorized payer for this '
          'member?',
      confirmLabel: 'Remove',
      confirmColor: DesignConstants.badRed,
      effects: const [
        BillingEffect(
          icon: Symbols.link_off_sharp,
          text:
              'They can no longer be set as the payer for new '
              'memberships.',
        ),
      ],
      warning:
          'Memberships they already pay for are unaffected — '
          'change those from the membership itself.',
    );

    if (!confirmed) return;
    bloc.add(
      UnlinkParentRequested(
        memberId: payeeMemberId,
        payerMemberId: payerMemberId,
      ),
    );
  }
}
