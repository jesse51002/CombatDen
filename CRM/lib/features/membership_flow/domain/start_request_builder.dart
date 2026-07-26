/// The single assembly point for the start request — the body of both
/// `POST /api/v1/member_memberships/` and its `/preview` counterpart, for both
/// purchase surfaces. One place to audit what either of them can send.
///
/// The ITEMS are built by each surface, because that is where the two
/// genuinely differ: the kiosk sends one `quantity: 1` line per training
/// person and narrows a retry to the memberships a landed start did not
/// create, while the wizard sends a staff-configured lineup carrying pack
/// quantities. What must never differ — the envelope's field set, and the
/// "no items, no request" rule that keeps an empty cart from taking a 400 —
/// lives here.
library;

import 'package:crm/features/member_details/data/models/member_memberships_start_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_payment.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';

/// The one wire request for this attempt, or null when [memberships] is empty
/// — nothing configured yet, or a retry with nothing left to send.
///
/// Returning null rather than an empty request is load-bearing on both
/// surfaces: an empty `memberships` list takes a 400, and on the kiosk a retry
/// whose set has emptied must send NOTHING rather than re-post the cart.
///
/// [payment] rides on PAY only, never on a preview.
MemberMembershipsStartRequest? buildStartRequest({
  required String payerMemberId,
  required String gymId,
  required String idempotencyKey,
  required ProrationBehavior prorationBehavior,
  required bool paidWithCash,
  required List<MemberMembershipsStartItem> memberships,
  MemberMembershipsStartPayment? payment,
}) {
  if (memberships.isEmpty) return null;
  return MemberMembershipsStartRequest(
    payerMemberId: payerMemberId,
    gymId: gymId,
    idempotencyKey: idempotencyKey,
    prorationBehavior: prorationBehavior,
    paidWithCash: paidWithCash,
    payment: payment,
    memberships: memberships,
  );
}
