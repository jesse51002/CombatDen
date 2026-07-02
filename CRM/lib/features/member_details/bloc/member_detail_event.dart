import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';

/// Events for the MemberDetailBloc.
sealed class MemberDetailEvent extends Equatable {
  const MemberDetailEvent();

  @override
  List<Object?> get props => [];
}

// ----- Load + UI -----

/// Load a member's detail. [gymId] scopes the sidebar
/// roster fetch (`getAllMembers`).
class MemberDetailRequested extends MemberDetailEvent {
  final String memberId;
  final String gymId;
  const MemberDetailRequested(
    this.memberId, {
    required this.gymId,
  });

  @override
  List<Object?> get props => [memberId, gymId];
}

class MemberSearchChanged extends MemberDetailEvent {
  final String query;
  const MemberSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

class MembershipPageChanged extends MemberDetailEvent {
  final int pageIndex;
  const MembershipPageChanged(this.pageIndex);

  @override
  List<Object?> get props => [pageIndex];
}

/// Clears the most recent mutation error after the UI
/// has shown it (e.g. after a SnackBar auto-dismiss).
class MemberActionErrorCleared extends MemberDetailEvent {
  const MemberActionErrorCleared();
}

// ----- Member profile mutations -----

class EditMemberRequested extends MemberDetailEvent {
  final MembersManagementUpdateRequest request;
  const EditMemberRequested(this.request);

  @override
  List<Object?> get props => [request];
}

class UpdateCardRequested extends MemberDetailEvent {
  final String paymentMethodId;

  /// The member whose saved card is being set. Null targets
  /// the currently viewed member; the start-memberships
  /// wizard sets it to the payer so the card can be edited
  /// from any launching page (e.g. a linked child's).
  final String? targetMemberId;
  const UpdateCardRequested(
    this.paymentMethodId, {
    this.targetMemberId,
  });

  @override
  List<Object?> get props => [paymentMethodId, targetMemberId];
}

class UnlinkPaymentRequested extends MemberDetailEvent {
  const UnlinkPaymentRequested();
}

/// Authorize a payer for a member (the sign-gated link).
/// [memberId] is the payee (the link's path member); [payerMemberId]
/// is authorized to pay for them AND is the waiver signer. The same
/// event serves both add directions — authorizing a payer for the
/// viewed member (payee = viewed) or authorizing the viewed member
/// to pay for someone (payer = viewed).
class LinkParentRequested extends MemberDetailEvent {
  final String memberId;
  final String payerMemberId;
  final String signerName;
  final bool consentAcknowledged;
  const LinkParentRequested({
    required this.memberId,
    required this.payerMemberId,
    required this.signerName,
    required this.consentAcknowledged,
  });

  @override
  List<Object?> get props => [
        memberId,
        payerMemberId,
        signerName,
        consentAcknowledged,
      ];
}

/// Remove a payer's authorization for a member, cascading a pair-scoped
/// cancel. [memberId] is the payee; [payerMemberId] is the payer being
/// removed. The backend cancels the member's live recurring memberships that
/// payer funds, then de-authorizes the pair. Preview the impact first
/// (MemberRepository.previewRemoveAuthorization).
class RemoveAuthorizationRequested extends MemberDetailEvent {
  final String memberId;
  final String payerMemberId;
  const RemoveAuthorizationRequested({
    required this.memberId,
    required this.payerMemberId,
  });

  @override
  List<Object?> get props => [memberId, payerMemberId];
}

/// Clears the remove-authorization outcome when the unlink
/// dialog closes, so a later remove run opens clean.
class RemoveAuthorizationOutcomeCleared extends MemberDetailEvent {
  const RemoveAuthorizationOutcomeCleared();
}

// ----- Membership mutations -----

/// Fire the one start-memberships POST (the wizard's PAY).
/// The outcome lands on the loaded state as `startResult`
/// (the per-membership breakdown) or `startError` (an HTTP
/// 400 validation / transport failure) — the wizard's
/// results step renders whichever arrives.
class StartMembershipsRequested extends MemberDetailEvent {
  final MemberMembershipsStartRequest request;
  const StartMembershipsRequested(this.request);

  @override
  List<Object?> get props => [request];
}

/// Clears the start-memberships outcome (result + error)
/// when the wizard closes, so a later wizard run opens
/// clean.
class StartMembershipsCleared extends MemberDetailEvent {
  const StartMembershipsCleared();
}

/// Clears the cancel-memberships outcome when the cancel
/// dialog closes, so a later cancel run opens clean.
class CancelMembershipOutcomeCleared extends MemberDetailEvent {
  const CancelMembershipOutcomeCleared();
}

/// Cancel ONE OR MORE memberships in one request (a single cancel is a
/// one-element list). The backend groups [itemIds] by payer and converges
/// each payer's subscription once.
class CancelMembershipRequested extends MemberDetailEvent {
  final List<String> itemIds;

  /// The focused member the cancel was launched from — the auth + gym-scope
  /// anchor for the request (the items themselves may be funded for other
  /// members; the backend resolves each item's own payer).
  final String memberId;

  const CancelMembershipRequested({
    required this.itemIds,
    required this.memberId,
  });

  @override
  List<Object?> get props => [itemIds, memberId];
}

/// Migrate a membership item to the plan's current active
/// price. NOTE: the merged contract does not accept a
/// target price id — only `item_id`, `member_id`, and
/// `proration_behavior`.
class UpdatePriceRequested extends MemberDetailEvent {
  final String itemId;
  final String memberId;
  final ProrationBehavior prorationBehavior;

  const UpdatePriceRequested({
    required this.itemId,
    required this.memberId,
    this.prorationBehavior = ProrationBehavior.noCharge,
  });

  @override
  List<Object?> get props =>
      [itemId, memberId, prorationBehavior];
}

/// Cross-plan upgrade: move [itemId] to [targetPlanId]'s active price,
/// charging the prorated difference when [prorationBehavior] prorates
/// (a downgrade charges nothing). [memberId] is the covered member.
class UpgradeMembershipRequested extends MemberDetailEvent {
  final String itemId;
  final String memberId;
  final String targetPlanId;
  final ProrationBehavior prorationBehavior;

  const UpgradeMembershipRequested({
    required this.itemId,
    required this.memberId,
    required this.targetPlanId,
    this.prorationBehavior = ProrationBehavior.prorateToAnchor,
  });

  @override
  List<Object?> get props =>
      [itemId, memberId, targetPlanId, prorationBehavior];
}

/// End a ONE-TIME / TRIAL membership early — sets its end date to
/// today. No charge, no Stripe action. [memberId] is the covered member.
class EndMembershipRequested extends MemberDetailEvent {
  final String itemId;
  final String memberId;

  const EndMembershipRequested({
    required this.itemId,
    required this.memberId,
  });

  @override
  List<Object?> get props => [itemId, memberId];
}

class FreezeAccountRequested extends MemberDetailEvent {
  final int freezeMonths;
  const FreezeAccountRequested(this.freezeMonths);

  @override
  List<Object?> get props => [freezeMonths];
}

class UnfreezeAccountRequested extends MemberDetailEvent {
  const UnfreezeAccountRequested();
}

class MarkPaidCashRequested extends MemberDetailEvent {
  final String itemId;
  final String memberId;
  const MarkPaidCashRequested({
    required this.itemId,
    required this.memberId,
  });

  @override
  List<Object?> get props => [itemId, memberId];
}

/// Commits adding applied-discount rows to a membership
/// — the named [discountIds] (by discount id, any type incl. a
/// `linked` family discount) frozen at their active value
/// version. A single-operation commit (the backend has no
/// combined add+remove); preview happens repository-direct.
class AddDiscountsRequested extends MemberDetailEvent {
  final String itemId;
  final String memberId;
  final List<String> discountIds;
  const AddDiscountsRequested({
    required this.itemId,
    required this.memberId,
    required this.discountIds,
  });

  @override
  List<Object?> get props => [itemId, memberId, discountIds];
}

/// Commits removing applied-discount rows from a
/// membership — the rows named by their
/// `applied_discount_id` ([appliedIds]). A single-operation
/// commit; preview happens repository-direct.
class RemoveDiscountsRequested extends MemberDetailEvent {
  final String itemId;
  final String memberId;
  final List<String> appliedIds;
  const RemoveDiscountsRequested({
    required this.itemId,
    required this.memberId,
    required this.appliedIds,
  });

  @override
  List<Object?> get props => [itemId, memberId, appliedIds];
}

// ----- Charges / refunds -----

class ChargeCardRequested extends MemberDetailEvent {
  final int amount;
  final String description;

  /// Whose Stripe customer is billed — the viewed member
  /// (self-pay) or their linked parent, picked in the
  /// charge dialog.
  final String paidByMemberId;

  /// An optional one-off card (a Stripe `pm_...`) entered at
  /// checkout: billed once then detached, leaving the payer's
  /// saved default untouched. Null bills the saved default.
  final String? paymentMethodId;

  /// When true the charge is settled OUT OF BAND (cash): the
  /// invoice is marked paid without charging any card. Mutually
  /// exclusive with [paymentMethodId].
  final bool paidCash;

  const ChargeCardRequested({
    required this.amount,
    required this.description,
    required this.paidByMemberId,
    this.paymentMethodId,
    this.paidCash = false,
  });

  @override
  List<Object?> get props => [
        amount,
        description,
        paidByMemberId,
        paymentMethodId,
        paidCash,
      ];
}

/// Clears the charge-card outcome (error) when the charge
/// dialog opens, so a prior charge's failure doesn't flash.
class ChargeCardOutcomeCleared extends MemberDetailEvent {
  const ChargeCardOutcomeCleared();
}

/// Clears the upgrade outcome (error) when the upgrade dialog
/// opens, so a prior upgrade's failure doesn't flash (mirrors
/// [ChargeCardOutcomeCleared]).
class UpgradeMembershipOutcomeCleared extends MemberDetailEvent {
  const UpgradeMembershipOutcomeCleared();
}

/// Clears the end-membership outcome (error) when the end dialog
/// opens, so a prior end's failure doesn't flash (mirrors
/// [UpgradeMembershipOutcomeCleared]).
class EndMembershipOutcomeCleared extends MemberDetailEvent {
  const EndMembershipOutcomeCleared();
}

/// NOTE: refund has no backend endpoint in the merged
/// contract (see `MemberRepository.refundCharge`).
class RefundChargeRequested extends MemberDetailEvent {
  final String chargeId;
  final int? amount;

  const RefundChargeRequested({
    required this.chargeId,
    this.amount,
  });

  @override
  List<Object?> get props => [chargeId, amount];
}

// ----- Class check-in -----

/// Check the viewed member into the occurrence of [classId] on
/// [occurrenceDate] + [occurrenceTime] — the occurrence's IDENTITY key, never
/// its effective/display date/time. The CRM is the staff surface
/// (`is_member: false`): a clean check-in is recorded, but one that hits a
/// gate warning is NOT recorded — the outcome lands on the loaded state as
/// `checkInResult` with `requiresConfirmation` true and the `warnings`, so the
/// dialog can offer "Check in anyway" (re-dispatched with [ignoreWarnings]
/// true) — or as `checkInError` on an unexpected failure.
class MemberCheckInRequested extends MemberDetailEvent {
  final String classId;
  final DateTime occurrenceDate;
  final String occurrenceTime;
  final bool ignoreWarnings;

  const MemberCheckInRequested({
    required this.classId,
    required this.occurrenceDate,
    required this.occurrenceTime,
    this.ignoreWarnings = false,
  });

  @override
  List<Object?> get props =>
      [classId, occurrenceDate, occurrenceTime, ignoreWarnings];
}

/// Clears the check-in outcome (result + error) when the check-in dialog opens
/// or closes, so a later run opens clean.
class MemberCheckInCleared extends MemberDetailEvent {
  const MemberCheckInCleared();
}

// ----- Class reserve (sign-up) -----

/// Reserve (sign up) the viewed member for the occurrence of [classId] on
/// [occurrenceDate] + [occurrenceTime] — the occurrence's IDENTITY key, never
/// its effective/display date/time — a single-member wrapper over the
/// schedule feature's `ScheduleRepository.signUp`, NOT attendance. Idempotent
/// (`SignupResponse.alreadySignedUp` on a repeat, no extra capacity
/// consumed); rejected with e.g. "Class is full" once the occurrence's
/// effective capacity is reached — surfaced as `reserveError`. There is no
/// "confirm anyway" override here (mirrors the schedule feature's own
/// "Sign up members" dialog): a reserve either succeeds or the room is full.
class MemberReserveRequested extends MemberDetailEvent {
  final String classId;
  final DateTime occurrenceDate;
  final String occurrenceTime;

  const MemberReserveRequested({
    required this.classId,
    required this.occurrenceDate,
    required this.occurrenceTime,
  });

  @override
  List<Object?> get props => [classId, occurrenceDate, occurrenceTime];
}

/// Clears the reserve outcome (result + error) when the check-in/reserve
/// dialog opens or closes, so a later run opens clean.
class MemberReserveCleared extends MemberDetailEvent {
  const MemberReserveCleared();
}

// ----- Invoice polling -----

/// One tick of the post-charge invoice poll. Dispatched by the
/// `InvoicePoller`'s timers (not the UI) after a charge / start /
/// refund / mark-paid-cash, on a fixed 5/10/15/30/60s schedule. Its
/// handler dumbly re-reads the billing surfaces (bumps `refreshToken`)
/// so a webhook-delivered invoice appears without a manual reload.
class InvoicePollRequested extends MemberDetailEvent {
  const InvoicePollRequested();
}
