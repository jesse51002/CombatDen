import 'package:equatable/equatable.dart';

/// Events for the MemberDetailBloc.
sealed class MemberDetailEvent extends Equatable {
  const MemberDetailEvent();

  @override
  List<Object?> get props => [];
}

/// Load member detail and sidebar member list.
class MemberDetailRequested extends MemberDetailEvent {
  final String crmUserId;

  const MemberDetailRequested(this.crmUserId);

  @override
  List<Object?> get props => [crmUserId];
}

/// Filter the sidebar member list by search query.
class MemberSearchChanged extends MemberDetailEvent {
  final String query;

  const MemberSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

/// Change the currently visible membership page in the
/// carousel.
class MembershipPageChanged extends MemberDetailEvent {
  final int pageIndex;

  const MembershipPageChanged(this.pageIndex);

  @override
  List<Object?> get props => [pageIndex];
}
