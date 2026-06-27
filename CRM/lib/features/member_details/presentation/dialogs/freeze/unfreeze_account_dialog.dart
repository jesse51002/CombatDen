import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Confirms unfreezing the viewed member — listing each frozen
/// membership that will resume — and returns `true` when the caller
/// should dispatch the unfreeze event. The bloc keys the request by
/// member id from state, so no body is needed here.
class UnfreezeAccountDialog {
  UnfreezeAccountDialog._();

  static Future<bool> show({
    required BuildContext context,
    required MemberDetailResponse member,
  }) {
    // The viewed member's own frozen memberships that will resume.
    final frozen = member.memberships
        .where((m) => m.status == MembershipStatus.frozen)
        .toList();

    final effects = frozen.isNotEmpty
        ? frozen
            .map(
              (m) => BillingEffect(
                icon: Symbols.play_circle_sharp,
                text: '${m.planName} — billing resumes on the '
                    'next scheduled cycle.',
              ),
            )
            .toList()
        : const [
            BillingEffect(
              icon: Symbols.play_circle_sharp,
              text: 'Billing resumes on the next scheduled '
                  'cycle for each membership.',
            ),
          ];

    return BillingConfirmationDialog.show(
      context: context,
      title: 'Unfreeze member',
      summary: 'Unfreezing resumes all of '
          '${member.firstName}\'s memberships '
          'and restarts recurring billing.',
      effects: effects,
      confirmLabel: 'Resume billing',
      confirmColor: DesignConstants.primaryColor,
    );
  }
}
