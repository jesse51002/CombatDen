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

/// Initial state before any data is loaded.
class MemberDetailInitial extends MemberDetailState {
  const MemberDetailInitial();
}

/// Loading state while fetching member data.
class MemberDetailLoading extends MemberDetailState {
  const MemberDetailLoading();
}

/// Successfully loaded member detail and sidebar list.
class MemberDetailLoaded extends MemberDetailState {
  final MemberDetailResponse member;
  final List<MemberSummary> allMembers;
  final List<MemberSummary> filteredMembers;
  final String searchQuery;
  final int currentMembershipIndex;

  const MemberDetailLoaded({
    required this.member,
    required this.allMembers,
    required this.filteredMembers,
    this.searchQuery = '',
    this.currentMembershipIndex = 0,
  });

  /// The currently visible membership in the carousel,
  /// or null if no memberships exist.
  MembershipInfo? get currentMembership {
    if (member.memberships.isEmpty) return null;
    return member.memberships[currentMembershipIndex];
  }

  MemberDetailLoaded copyWith({
    MemberDetailResponse? member,
    List<MemberSummary>? allMembers,
    List<MemberSummary>? filteredMembers,
    String? searchQuery,
    int? currentMembershipIndex,
  }) {
    return MemberDetailLoaded(
      member: member ?? this.member,
      allMembers: allMembers ?? this.allMembers,
      filteredMembers:
          filteredMembers ?? this.filteredMembers,
      searchQuery: searchQuery ?? this.searchQuery,
      currentMembershipIndex: currentMembershipIndex ??
          this.currentMembershipIndex,
    );
  }

  @override
  List<Object?> get props => [
        member,
        allMembers,
        filteredMembers,
        searchQuery,
        currentMembershipIndex,
      ];
}

/// Error state when loading fails.
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
