import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';

/// States for the [MemberCreateBloc]. The create form is reusable across
/// hosts (the add-member flow, the in-wizard new-member dialog); the bloc
/// owns only the submit → duplicate/created/failure transitions.
sealed class MemberCreateState extends Equatable {
  const MemberCreateState();

  @override
  List<Object?> get props => [];
}

/// The initial / editing state — no request in flight.
class MemberCreateIdle extends MemberCreateState {
  const MemberCreateIdle();
}

/// A create (or create-anyway) POST is in flight.
class MemberCreateSubmitting extends MemberCreateState {
  const MemberCreateSubmitting();
}

/// The backend gated the create on a same-identity duplicate (409, nothing
/// written). [pendingRequest] is the exact request that was blocked —
/// re-sent with `allow_duplicate: true` on create-anyway.
class MemberCreateDuplicate extends MemberCreateState {
  final List<DuplicateMemberMatch> matches;
  final MembersManagementCreateRequest pendingRequest;

  const MemberCreateDuplicate({
    required this.matches,
    required this.pendingRequest,
  });

  @override
  List<Object?> get props => [matches, pendingRequest];
}

/// A member is ready — either just created, or an existing duplicate the
/// host chose to continue with. Carries only the member id; the host holds
/// the identity it needs for its confirmation.
class MemberCreated extends MemberCreateState {
  final String memberId;

  const MemberCreated(this.memberId);

  @override
  List<Object?> get props => [memberId];
}

/// The create failed. [needsStripeSetup] is true for the 400 the backend
/// returns when the gym has no Stripe Connect account — the host points the
/// user at Settings instead of showing a generic error.
class MemberCreateFailure extends MemberCreateState {
  final String message;
  final bool needsStripeSetup;

  const MemberCreateFailure(
    this.message, {
    this.needsStripeSetup = false,
  });

  @override
  List<Object?> get props => [message, needsStripeSetup];
}
