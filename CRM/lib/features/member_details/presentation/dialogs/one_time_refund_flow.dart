import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/charge_kind.dart';
import 'package:crm/features/member_details/data/models/charge_status.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_one_time_membership_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/payment_invoice_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// Refund a ONE-TIME / TRIAL membership's purchase, then offer to also cancel
/// it. Refund + cancel are SEPARATE actions, but a refund usually pairs with
/// cancelling the pack — so after a submitted refund this opens
/// [CancelOneTimeMembershipDialog] (its own confirm → processing → success), rather
/// than firing the cancellation in the background.
///
/// Opens the membership's **purchase invoice** in the same rich popup
/// Payment History uses ([PaymentInvoiceDialog]): the full breakdown, the
/// already-refunded amount, and a refund button for the remaining balance
/// (full or partial). The charge is resolved from the member's payment
/// history by matching the succeeded payment whose line items carry this
/// membership's `item_id` — found **regardless of how much is already
/// refunded**, so pressing Refund on an already-refunded pack shows the
/// invoice (with its refund history) instead of a "nothing found" dead-end.
Future<void> runOneTimeRefundFlow(
  BuildContext context, {
  required MemberDetailResponse member,
  required MembershipInfo membership,
  required String coveredMemberId,
  required String coveredMemberName,
  required bool allowEnd,
}) async {
  final itemId = membership.itemId;
  final repo = MemberRepository(apiClient: ApiClient());

  final PaymentRecord? charge;
  try {
    charge = await _findMembershipCharge(repo, member.memberId, itemId);
  } catch (_) {
    if (!context.mounted) return;
    await AppDialog.show<void>(
      context: context,
      title: 'Could not load charges',
      body: Text(
        "Could not load this member's payment history to find the "
        'purchase invoice. Please try again.',
        style: DesignConstants.p.copyWith(color: DesignConstants.text),
      ),
      primaryLabel: 'OK',
      primaryOnPressed: (c) => Navigator.of(c).pop(),
      secondaryLabel: null,
    );
    return;
  }
  if (!context.mounted) return;

  if (charge == null) {
    await AppDialog.show<void>(
      context: context,
      title: 'No purchase invoice yet',
      body: Text(
        "This membership's purchase invoice isn't available yet — once "
        'the charge settles it shows in Payment History, where it can be '
        'refunded.',
        style: DesignConstants.p.copyWith(color: DesignConstants.text),
      ),
      primaryLabel: 'OK',
      primaryOnPressed: (c) => Navigator.of(c).pop(),
      secondaryLabel: null,
    );
    return;
  }

  // Show the full purchase invoice (refund history + full/partial refund),
  // exactly like Payment History. Resolves true once a refund is submitted.
  final refunded =
      await PaymentInvoiceDialog.show(context: context, payment: charge) ??
          false;
  if (!refunded || !allowEnd || !context.mounted) return;

  // Offer to also cancel the pack. The cancel dialog IS the "cancel this
  // membership?" confirm plus its own visible processing → success step
  // ("Keep membership" = "not now") — so the cancellation is never a silent
  // background dispatch.
  await CancelOneTimeMembershipDialog.show(
    context: context,
    membership: membership,
    coveredMemberId: coveredMemberId,
    coveredMemberName: coveredMemberName,
  );
}

/// The succeeded payment whose line items include [itemId] — the charge
/// that bought this one-time membership. Matched **regardless of how much
/// is already refunded** (so a fully-refunded pack still resolves and its
/// invoice can be shown). Returns null when no such charge exists yet (a
/// not-yet-settled purchase or a $0 trial); THROWS on a fetch failure so a
/// transient 500 / network drop is not misreported as "no invoice".
Future<PaymentRecord?> _findMembershipCharge(
  MemberRepository repo,
  String memberId,
  String itemId,
) async {
  // Searches only the first page (100 most-recent charges). A one-time pack's
  // purchase is normally recent, so page 1 suffices; a member with >100 newer
  // charges since the purchase would need pagination here to still find it —
  // not handled (the same charge is always refundable from Payment History).
  final payments =
      await repo.getPayments(memberId, limit: 100, offset: 0);
  for (final p in payments) {
    if (p.kind == ChargeKind.payment &&
        p.status == ChargeStatus.succeeded &&
        p.lineItems.any((l) => l.itemId == itemId)) {
      return p;
    }
  }
  return null;
}
