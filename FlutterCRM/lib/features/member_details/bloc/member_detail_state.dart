import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';

/// States for the MemberDetailBloc.
sealed class MemberDetailState extends Equatable {
  const MemberDetailState();

  @override
  List<Object?> get props => [];
}

class MemberDetailInitial extends MemberDetailState {
  const MemberDetailInitial();
}

class MemberDetailLoading extends MemberDetailState {
  const MemberDetailLoading();
}

/// Successfully loaded. `isMutating` is true while a
/// background mutation (freeze, cancel, update, etc.) is
/// in flight; `actionError` holds the most recent
/// mutation failure — the UI is expected to surface it
/// (e.g. via SnackBar) and then dispatch
/// [MemberActionErrorCleared].
class MemberDetailLoaded extends MemberDetailState {
  final MemberDetailResponse member;
  final List<MemberSummary> allMembers;
  final List<MemberSummary> filteredMembers;
  final String searchQuery;
  final int currentMembershipIndex;
  final bool isMutating;
  final String? actionError;

  /// Monotonic counter bumped on every successful mutation
  /// refresh so BlocBuilder rebuilds even when the refreshed
  /// [MemberDetailResponse] is deep-equal to the previous one
  /// (e.g. backend eventual consistency returns stale data).
  final int refreshToken;

  const MemberDetailLoaded({
    required this.member,
    required this.allMembers,
    required this.filteredMembers,
    this.searchQuery = '',
    this.currentMembershipIndex = 0,
    this.isMutating = false,
    this.actionError,
    this.refreshToken = 0,
  });

  MembershipInfo? get currentMembership {
    if (member.memberships.isEmpty) return null;
    if (currentMembershipIndex >=
        member.memberships.length) {
      return member.memberships.first;
    }
    return member.memberships[currentMembershipIndex];
  }

  MemberDetailLoaded copyWith({
    MemberDetailResponse? member,
    List<MemberSummary>? allMembers,
    List<MemberSummary>? filteredMembers,
    String? searchQuery,
    int? currentMembershipIndex,
    bool? isMutating,
    String? actionError,
    bool clearActionError = false,
    int? refreshToken,
  }) {
    return MemberDetailLoaded(
      member: member ?? this.member,
      allMembers: allMembers ?? this.allMembers,
      filteredMembers:
          filteredMembers ?? this.filteredMembers,
      searchQuery: searchQuery ?? this.searchQuery,
      currentMembershipIndex: currentMembershipIndex ??
          this.currentMembershipIndex,
      isMutating: isMutating ?? this.isMutating,
      actionError: clearActionError
          ? null
          : (actionError ?? this.actionError),
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }

  @override
  List<Object?> get props => [
        member,
        allMembers,
        filteredMembers,
        searchQuery,
        currentMembershipIndex,
        isMutating,
        actionError,
        refreshToken,
      ];
}

class MemberDetailError extends MemberDetailState {
  final String message;
  final String crmUserId;

  const MemberDetailError(
    this.message, {
    required this.crmUserId,
  });

  @override
  List<Object?> get props => [message, crmUserId];
}
