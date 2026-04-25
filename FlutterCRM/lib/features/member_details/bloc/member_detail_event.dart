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

class MemberDetailRequested extends MemberDetailEvent {
  final String crmUserId;
  const MemberDetailRequested(this.crmUserId);

  @override
  List<Object?> get props => [crmUserId];
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
  final String parentCrmUserId;

  /// When null, links the currently viewed member to the
  /// chosen parent. When set, links the given child to
  /// the chosen parent (manage-linked-accounts flow).
  final String? childCrmUserId;
  const LinkParentRequested(
    this.parentCrmUserId, {
    this.childCrmUserId,
  });

  @override
  List<Object?> get props => [parentCrmUserId, childCrmUserId];
}

class UnlinkParentRequested extends MemberDetailEvent {
  /// When null, unlinks the currently viewed member from
  /// their parent. When set, unlinks the given child from
  /// the currently viewed parent (manage-linked-accounts
  /// flow).
  final String? childCrmUserId;
  const UnlinkParentRequested({this.childCrmUserId});

  @override
  List<Object?> get props => [childCrmUserId];
}

// ----- Membership mutations -----

class StartMembershipRequested extends MemberDetailEvent {
  final MemberMembershipsStartRequest request;
  const StartMembershipRequested(this.request);

  @override
  List<Object?> get props => [request];
}

class CancelMembershipRequested extends MemberDetailEvent {
  final String itemId;

  /// The covered person whose slot on this membership is
  /// being cancelled — may be the primary member or a
  /// linked child. Never assume `member.crmUserId`.
  final String crmUserId;

  const CancelMembershipRequested({
    required this.itemId,
    required this.crmUserId,
  });

  @override
  List<Object?> get props => [itemId, crmUserId];
}

class UpdatePriceRequested extends MemberDetailEvent {
  final String itemId;
  final String crmUserId;
  final String newPriceId;
  final bool prorate;

  const UpdatePriceRequested({
    required this.itemId,
    required this.crmUserId,
    required this.newPriceId,
    this.prorate = false,
  });

  @override
  List<Object?> get props =>
      [itemId, crmUserId, newPriceId, prorate];
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
  final String crmUserId;
  const MarkPaidCashRequested({
    required this.itemId,
    required this.crmUserId,
  });

  @override
  List<Object?> get props => [itemId, crmUserId];
}

/// Replaces the full discount set on a membership with
/// [discountIds]. Use this for both add and remove flows.
class UpdateDiscountsRequested extends MemberDetailEvent {
  final String itemId;
  final String crmUserId;
  final List<String> discountIds;
  const UpdateDiscountsRequested({
    required this.itemId,
    required this.crmUserId,
    required this.discountIds,
  });

  @override
  List<Object?> get props =>
      [itemId, crmUserId, discountIds];
}

// ----- Charges / refunds (pending backend) -----

class ChargeCardRequested extends MemberDetailEvent {
  final int amount;
  final String description;

  const ChargeCardRequested({
    required this.amount,
    required this.description,
  });

  @override
  List<Object?> get props => [amount, description];
}

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
