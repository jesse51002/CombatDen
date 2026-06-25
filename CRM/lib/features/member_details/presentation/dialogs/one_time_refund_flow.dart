import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/charge_kind.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/refund_charge_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// Refund a ONE-TIME / TRIAL membership's charge, then offer to also end
/// it. Refund + end are SEPARATE actions, but a refund usually pairs with
/// ending the pack — so after a submitted refund this prompts "also end?".
///
/// The charge is resolved from the member's payment history by matching a
/// payment whose line items carry this membership's `item_id` and that
/// still has a refundable balance. When none is found, the staff are
/// pointed at Payment History.
Future<void> runOneTimeRefundFlow(
  BuildContext context, {
  required MemberDetailResponse member,
  required MembershipInfo membership,
  required String coveredMemberId,
  required bool allowEnd,
}) async {
  final itemId = membership.itemId;
  final bloc = context.read<MemberDetailBloc>();
  final repo = MemberRepository(apiClient: ApiClient());

  final charge =
      await _findRefundableCharge(repo, member.memberId, itemId);
  if (!context.mounted) return;

  if (charge == null) {
    await AppDialog.show<void>(
      context: context,
      title: 'No refundable charge',
      body: Text(
        'No refundable charge was found for this membership. Check '
        'Payment History to refund a specific charge.',
        style: DesignConstants.p.copyWith(color: DesignConstants.text),
      ),
      primaryLabel: 'OK',
      primaryOnPressed: (c) => Navigator.of(c).pop(),
      secondaryLabel: null,
    );
    return;
  }

  final submitted =
      await RefundChargeDialog.show(context: context, charge: charge) ??
          false;
  if (!submitted || !allowEnd || !context.mounted) return;

  final alsoEnd = await AppDialog.show<bool>(
        context: context,
        title: 'Refund submitted',
        body: Text(
          'Also end this membership now? It will be marked ended.',
          style:
              DesignConstants.p.copyWith(color: DesignConstants.text),
        ),
        primaryLabel: 'End membership',
        primaryColor: DesignConstants.badRed,
        primaryOnPressed: (c) => Navigator.of(c).pop(true),
        secondaryLabel: 'Not now',
        secondaryOnPressed: (c) => Navigator.of(c).pop(false),
      ) ??
      false;
  if (alsoEnd) {
    bloc.add(
      EndMembershipRequested(itemId: itemId, memberId: coveredMemberId),
    );
  }
}

/// The newest still-refundable payment (not a refund row) whose line
/// items include [itemId]. Returns null on none / a fetch failure.
Future<PaymentRecord?> _findRefundableCharge(
  MemberRepository repo,
  String memberId,
  String itemId,
) async {
  try {
    final payments =
        await repo.getPayments(memberId, limit: 100, offset: 0);
    for (final p in payments) {
      if (p.kind == ChargeKind.payment &&
          p.netAmount > 0 &&
          p.lineItems.any((l) => l.itemId == itemId)) {
        return p;
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}
