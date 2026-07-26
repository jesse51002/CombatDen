/// How the staff flow's cart becomes a wire request — the desk's half of the
/// shared `start_request_builder.dart`, which owns the envelope.
///
/// Two rules live here and nowhere else: which memberships a given attempt
/// carries (the whole cart on a first attempt, only the UN-CREATED ones on a
/// retry), and when the one-off card may ride along. Both are double-charge
/// defences, so both are pure functions with their own tests rather than
/// conditions spread through a widget.
library;

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_payment.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/features/membership_flow/domain/start_request_builder.dart';

/// The identity ONE membership has across a start and its retries: the person
/// and the plan. The desk sells several memberships to one person, so a
/// member id alone cannot say which of them the backend created.
String membershipKey(String memberId, String planId) => '$memberId·$planId';

/// The same identity read off a landed result row.
String resultKey(MemberMembershipsStartResultItem item) =>
    membershipKey(item.memberId, item.planId);

/// The (member, plan) pairs a RETRY may re-send: every item of the landed
/// start the backend did not confirm as `created`. Null when nothing has
/// landed.
///
/// Null and empty must stay distinct, and that is the whole defence. Null
/// means "nothing landed, send the cart"; EMPTY means "send nothing". Collapse
/// them and a retry re-posts memberships that already exist under a NEW
/// idempotency key — which the backend's `ON CONFLICT (idempotency_key)`
/// replay guard cannot dedupe, so the payer is charged twice. Keying on "not
/// created" rather than "failed" matters for the same reason: a
/// `[created, unknown]` response has no failed rows and still needs a retry.
Set<String>? retryScopeFor(MemberMembershipsStartResponse? result) =>
    result == null
        ? null
        : {
            for (final item in result.results)
              if (!item.isCreated) resultKey(item),
          };

/// Whether one membership is in the request the flow would assemble right now.
bool isBeingCharged({
  required String memberId,
  required String planId,
  required Set<String>? retryScope,
}) =>
    retryScope?.contains(membershipKey(memberId, planId)) ?? true;

/// This attempt's wire items, in roster then pick order.
///
/// Only TRAINING people contribute; a payer buying nothing for themselves is
/// identity on the envelope, not a line in the cart.
List<MemberMembershipsStartItem> startItemsFor({
  required List<MembershipWizardPerson> people,
  required Map<String, List<MembershipWizardDraft>> drafts,
  Set<String>? retryScope,
}) {
  final items = <MemberMembershipsStartItem>[];
  for (final person in people) {
    if (!person.training) continue;
    for (final draft in drafts[person.memberId] ??
        const <MembershipWizardDraft>[]) {
      if (!isBeingCharged(
        memberId: person.memberId,
        planId: draft.plan.planId,
        retryScope: retryScope,
      )) {
        continue;
      }
      final item = draft.toItem(person.memberId);
      if (item != null) items.add(item);
    }
  }
  return items;
}

/// Why the captured one-off card cannot pay for this cart, or null when it
/// can.
///
/// The old wizard simply ignored the card once the cart turned recurring or
/// cash went on — staff saw a card chip they had entered and a charge that
/// never touched it. Naming the blocker makes the surface able to say so.
enum OneOffCardBlock {
  /// Cash is on. Nothing is charged to any card.
  paidWithCash,

  /// A recurring membership can only bill the payer's SAVED default (the
  /// backend rejects a start that mixes recurring with a non-default card), so
  /// the whole request bills that card and the one-off has nothing to pay.
  cartHasRecurring,

  /// Nothing in the cart bills once, so there is no one-time invoice for it.
  cartHasNoOneTime,
}

/// Which blocker applies, or null when the one-off card is what pays today's
/// one-time invoice. Answered whether or not a card has actually been
/// captured, so a surface can explain the option BEFORE staff enter a number.
OneOffCardBlock? oneOffCardBlockFor({
  required bool paidWithCash,
  required bool hasOneTime,
  required bool hasRecurring,
}) {
  if (paidWithCash) return OneOffCardBlock.paidWithCash;
  if (hasRecurring) return OneOffCardBlock.cartHasRecurring;
  if (!hasOneTime) return OneOffCardBlock.cartHasNoOneTime;
  return null;
}

/// The one wire request for this attempt, or null when there is nothing to
/// send.
///
/// [forPay] is what decides whether the card rides: a preview never carries a
/// payment, and the one-off card only ever carries on a cart with no blocker.
/// It is sent with `set_default` false — it pays today's one-time invoice once
/// (attach → pay → detach) and never becomes the payer's saved card.
MemberMembershipsStartRequest? buildWizardRequest({
  required String payerMemberId,
  required String gymId,
  required String idempotencyKey,
  required ProrationBehavior prorationBehavior,
  required bool paidWithCash,
  required List<MemberMembershipsStartItem> memberships,
  required CustomCardCapture? customCard,
  required OneOffCardBlock? oneOffCardBlock,
  bool forPay = false,
}) {
  final usesCard =
      forPay && oneOffCardBlock == null && customCard != null;
  return buildStartRequest(
    payerMemberId: payerMemberId,
    gymId: gymId,
    idempotencyKey: idempotencyKey,
    prorationBehavior: prorationBehavior,
    paidWithCash: paidWithCash,
    memberships: memberships,
    payment: usesCard
        ? MemberMembershipsStartPayment(paymentMethodId: customCard.pmId)
        : null,
  );
}
