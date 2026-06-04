import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/paying_for_member.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Confirms resuming billing for a frozen account — listing
/// every affected member — and returns `true` when the caller
/// should dispatch the unfreeze event. The bloc keys the
/// request by member id from state, so no body is needed here.
class UnfreezeAccountDialog {
  UnfreezeAccountDialog._();

  static Future<bool> show({
    required BuildContext context,
    required MemberDetailResponse member,
  }) {
    final byId = <String, PayingForMember>{};
    for (final m in member.memberships) {
      for (final p in m.payingFor) {
        byId.putIfAbsent(p.memberId, () => p);
      }
    }
    final affected = byId.values
        .map(
          (p) => BillingAffectedPerson(
            fullName: p.fullName,
            initial: p.firstName.isNotEmpty
                ? p.firstName[0].toUpperCase()
                : '?',
            photoUrl: p.photoUrl,
          ),
        )
        .toList();

    return BillingConfirmationDialog.show(
      context: context,
      title: 'Resume billing',
      summary: 'Unfreezing resumes every membership on this '
          'account and restarts recurring billing.',
      effects: const [
        BillingEffect(
          icon: Symbols.play_circle_sharp,
          text: 'Billing resumes on the next scheduled cycle '
              'for each membership.',
        ),
      ],
      affected: affected,
      confirmLabel: 'Resume billing',
      confirmColor: DesignConstants.primaryColor,
    );
  }
}
