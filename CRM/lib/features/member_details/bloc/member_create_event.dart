import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/members_management_create_request.dart';

/// Events for the [MemberCreateBloc].
sealed class MemberCreateEvent extends Equatable {
  const MemberCreateEvent();

  @override
  List<Object?> get props => [];
}

/// Submit a new member. On an unconfirmed same-identity duplicate the bloc
/// lands on [MemberCreateDuplicate] instead of creating.
class MemberCreateSubmitted extends MemberCreateEvent {
  final MembersManagementCreateRequest request;

  const MemberCreateSubmitted(this.request);

  @override
  List<Object?> get props => [request];
}

/// Confirm and create anyway — re-sends the pending duplicate request with
/// `allow_duplicate: true`. Only meaningful from [MemberCreateDuplicate].
class MemberCreateAnywayRequested extends MemberCreateEvent {
  const MemberCreateAnywayRequested();
}

/// Skip creation and continue with an existing member (a duplicate match) —
/// emits [MemberCreated] without a POST.
class MemberCreateUseExisting extends MemberCreateEvent {
  final String memberId;

  const MemberCreateUseExisting(this.memberId);

  @override
  List<Object?> get props => [memberId];
}

/// Reset back to idle (e.g. "back to edit" from the duplicate step).
class MemberCreateReset extends MemberCreateEvent {
  const MemberCreateReset();
}
