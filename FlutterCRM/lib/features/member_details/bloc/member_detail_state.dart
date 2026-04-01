import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';

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

  const MemberDetailLoaded({
    required this.member,
    required this.allMembers,
    required this.filteredMembers,
    this.searchQuery = '',
  });

  MemberDetailLoaded copyWith({
    MemberDetailResponse? member,
    List<MemberSummary>? allMembers,
    List<MemberSummary>? filteredMembers,
    String? searchQuery,
  }) {
    return MemberDetailLoaded(
      member: member ?? this.member,
      allMembers: allMembers ?? this.allMembers,
      filteredMembers:
          filteredMembers ?? this.filteredMembers,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [
        member,
        allMembers,
        filteredMembers,
        searchQuery,
      ];
}

/// Error state when loading fails.
class MemberDetailError extends MemberDetailState {
  final String message;

  const MemberDetailError(this.message);

  @override
  List<Object?> get props => [message];
}
