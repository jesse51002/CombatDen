import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Confirms unlinking an account from its parent payer, then
/// dispatches [UnlinkParentRequested].
///
/// When [childMemberId] is null the currently-viewed member
/// is unlinked from their parent; when set, the given child
/// is unlinked from the currently-viewed parent (the
/// manage-linked-accounts flow).
class UnlinkParentDialog {
  UnlinkParentDialog._();

  static Future<void> show({
    required BuildContext context,
    required String subjectName,
    String? childMemberId,
  }) async {
    final bloc = context.read<MemberDetailBloc>();
    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Unlink account',
      summary:
          'Unlink $subjectName from the paying account?',
      confirmLabel: 'Unlink',
      confirmColor: DesignConstants.badRed,
      effects: const [
        BillingEffect(
          icon: Symbols.link_off_sharp,
          text:
              'They will bill independently going forward.',
        ),
      ],
      warning:
          'Any linked-account discount on the shared plan '
          'will be re-evaluated.',
    );

    if (!confirmed) return;
    bloc.add(
      UnlinkParentRequested(childMemberId: childMemberId),
    );
  }
}
