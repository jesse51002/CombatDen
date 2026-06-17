import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';

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
  const UpdateCardRequested(this.paymentMethodId);

  @override
  List<Object?> get props => [paymentMethodId];
}

class UnlinkPaymentRequested extends MemberDetailEvent {
  const UnlinkPaymentRequested();
}

class LinkParentRequested extends MemberDetailEvent {
  final String parentMemberId;

  /// When null, links the currently viewed member to the
  /// chosen parent. When set, links the given child to
  /// the chosen parent (manage-linked-accounts flow).
  final String? childMemberId;
  const LinkParentRequested(
    this.parentMemberId, {
    this.childMemberId,
  });

  @override
  List<Object?> get props =>
      [parentMemberId, childMemberId];
}

class UnlinkParentRequested extends MemberDetailEvent {
  /// When null, unlinks the currently viewed member from
  /// their parent. When set, unlinks the given child from
  /// the currently viewed parent (manage-linked-accounts
  /// flow).
  final String? childMemberId;
  const UnlinkParentRequested({this.childMemberId});

  @override
  List<Object?> get props => [childMemberId];
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

class CancelMembershipRequested extends MemberDetailEvent {
  final String itemId;

  /// The covered person whose slot on this membership is
  /// being cancelled — may be the primary member or a
  /// linked child. Never assume `member.memberId`.
  final String memberId;

  const CancelMembershipRequested({
    required this.itemId,
    required this.memberId,
  });

  @override
  List<Object?> get props => [itemId, memberId];
}

/// Migrate a membership item to the plan's current active
/// price. NOTE: the merged contract does not accept a
/// target price id — only `item_id`, `member_id`, and
/// `prorate`.
class UpdatePriceRequested extends MemberDetailEvent {
  final String itemId;
  final String memberId;
  final bool prorate;

  const UpdatePriceRequested({
    required this.itemId,
    required this.memberId,
    this.prorate = false,
  });

  @override
  List<Object?> get props => [itemId, memberId, prorate];
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

  const ChargeCardRequested({
    required this.amount,
    required this.description,
    required this.paidByMemberId,
  });

  @override
  List<Object?> get props =>
      [amount, description, paidByMemberId];
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
