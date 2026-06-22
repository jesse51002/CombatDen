import 'package:equatable/equatable.dart';

import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
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

  /// True while the wizard's start-memberships POST is in
  /// flight. Separate from [isMutating] so the wizard's
  /// results step owns its own loading treatment.
  final bool isStartingMemberships;

  /// The last start-memberships breakdown (per-membership
  /// created/failed). Rendered by the wizard's results
  /// step; cleared via [StartMembershipsCleared].
  final MemberMembershipsStartResponse? startResult;

  /// The last start-memberships failure (HTTP 400 message
  /// or transport error). Kept off [actionError] so the
  /// screen-level error dialog doesn't swallow it while
  /// the wizard is open.
  final String? startError;

  /// True while the charge-card POST is in flight. Separate
  /// from [isMutating] so the charge dialog owns its own
  /// loading + success treatment (mirrors
  /// [isStartingMemberships]).
  final bool isChargingCard;

  /// Monotonic token bumped once a charge succeeds. The charge
  /// dialog watches it to flip to its success step; the
  /// confirmation is rendered from the dialog's own retained
  /// amount / card / reason, so no result payload is needed.
  final int chargeCardSuccess;

  /// The last charge-card failure. Kept off [actionError] so
  /// the screen-level error dialog doesn't swallow it while
  /// the charge dialog is open (mirrors [startError]).
  final String? chargeCardError;

  /// Monotonic counter bumped on every successful mutation
  /// refresh so BlocBuilder rebuilds even when the
  /// refreshed [MemberDetailResponse] is deep-equal to the
  /// previous one (e.g. backend eventual consistency
  /// returns stale data).
  final int refreshToken;

  const MemberDetailLoaded({
    required this.member,
    required this.allMembers,
    required this.filteredMembers,
    this.searchQuery = '',
    this.currentMembershipIndex = 0,
    this.isMutating = false,
    this.actionError,
    this.isStartingMemberships = false,
    this.startResult,
    this.startError,
    this.isChargingCard = false,
    this.chargeCardSuccess = 0,
    this.chargeCardError,
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
    bool? isStartingMemberships,
    MemberMembershipsStartResponse? startResult,
    String? startError,
    bool clearStartOutcome = false,
    bool? isChargingCard,
    int? chargeCardSuccess,
    String? chargeCardError,
    bool clearChargeOutcome = false,
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
      isStartingMemberships: isStartingMemberships ??
          this.isStartingMemberships,
      startResult: clearStartOutcome
          ? null
          : (startResult ?? this.startResult),
      startError: clearStartOutcome
          ? null
          : (startError ?? this.startError),
      isChargingCard: isChargingCard ?? this.isChargingCard,
      chargeCardSuccess:
          chargeCardSuccess ?? this.chargeCardSuccess,
      chargeCardError: clearChargeOutcome
          ? null
          : (chargeCardError ?? this.chargeCardError),
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
        isStartingMemberships,
        startResult,
        startError,
        isChargingCard,
        chargeCardSuccess,
        chargeCardError,
        refreshToken,
      ];
}

class MemberDetailError extends MemberDetailState {
  final String message;
  final String memberId;

  const MemberDetailError(
    this.message, {
    required this.memberId,
  });

  @override
  List<Object?> get props => [message, memberId];
}
