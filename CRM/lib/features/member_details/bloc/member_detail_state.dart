import 'package:equatable/equatable.dart';

import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/member_details/data/models/cancel_outcome.dart';
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

  /// True while the cancel-memberships DELETE is in flight.
  /// Separate from [isMutating] so the cancel dialog owns its
  /// own loading + completion treatment (mirrors
  /// [isStartingMemberships] / [isChargingCard]).
  final bool isCancellingMemberships;

  /// The outcome of the last cancel-memberships request.
  /// Rendered by the cancel dialog's completion step;
  /// cleared via [CancelMembershipOutcomeCleared].
  final CancelOutcome? cancelOutcome;

  /// True while the remove-authorization POST is in flight.
  /// Separate from [isMutating] so the remove-authorization
  /// dialog owns its own loading + completion treatment
  /// (mirrors [isCancellingMemberships]).
  final bool isRemovingAuthorization;

  /// The outcome of the last remove-authorization request —
  /// which funded memberships the cascading cancel cancelled.
  /// Rendered by the remove-authorization dialog's completion
  /// step; cleared via [RemoveAuthorizationOutcomeCleared].
  final CancelOutcome? removeAuthorizationOutcome;

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

  /// True while the upgrade POST is in flight. Separate from
  /// [isMutating] so the upgrade dialog owns its own loading +
  /// success treatment (mirrors [isChargingCard]).
  final bool isUpgrading;

  /// Monotonic token bumped once an upgrade succeeds. The upgrade
  /// dialog watches it to flip to its success step; the
  /// confirmation is rendered from the picked plan name.
  final int upgradeSuccess;

  /// The last upgrade failure. Kept off [actionError] so the
  /// screen-level error dialog doesn't swallow it while the
  /// upgrade dialog is open (mirrors [chargeCardError]).
  final String? upgradeError;

  /// True while the end-membership POST is in flight. Separate from
  /// [isMutating] so the end dialog owns its own loading + success
  /// treatment (mirrors [isUpgrading]).
  final bool isEnding;

  /// Monotonic token bumped once an end succeeds. The end dialog
  /// watches it to flip to its success step.
  final int endSuccess;

  /// The last end-membership failure. Kept off [actionError] so the
  /// screen-level error dialog doesn't swallow it while the end dialog
  /// is open (mirrors [upgradeError]).
  final String? endError;

  /// True while the class check-in POST is in flight. Separate
  /// from [isMutating] so the check-in dialog owns its own
  /// loading + terminal treatment (mirrors [isChargingCard]).
  final bool isCheckingIn;

  /// The last check-in's result — a recorded attendance (with any
  /// non-blocking warnings) or an idempotent repeat. Rendered by the
  /// check-in dialog's terminal step; cleared via [MemberCheckInCleared].
  final CheckInResponse? checkInResult;

  /// The last check-in failure (an unexpected error). Kept off
  /// [actionError] so the screen-level error dialog doesn't swallow it
  /// while the check-in dialog is open (mirrors [chargeCardError]).
  final String? checkInError;

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
    this.isCancellingMemberships = false,
    this.cancelOutcome,
    this.isRemovingAuthorization = false,
    this.removeAuthorizationOutcome,
    this.isChargingCard = false,
    this.chargeCardSuccess = 0,
    this.chargeCardError,
    this.isUpgrading = false,
    this.upgradeSuccess = 0,
    this.upgradeError,
    this.isEnding = false,
    this.endSuccess = 0,
    this.endError,
    this.isCheckingIn = false,
    this.checkInResult,
    this.checkInError,
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
    bool? isCancellingMemberships,
    CancelOutcome? cancelOutcome,
    bool clearCancelOutcome = false,
    bool? isRemovingAuthorization,
    CancelOutcome? removeAuthorizationOutcome,
    bool clearRemoveAuthorizationOutcome = false,
    bool? isChargingCard,
    int? chargeCardSuccess,
    String? chargeCardError,
    bool clearChargeOutcome = false,
    bool? isUpgrading,
    int? upgradeSuccess,
    String? upgradeError,
    bool clearUpgradeOutcome = false,
    bool? isEnding,
    int? endSuccess,
    String? endError,
    bool clearEndOutcome = false,
    bool? isCheckingIn,
    CheckInResponse? checkInResult,
    String? checkInError,
    bool clearCheckInOutcome = false,
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
      isCancellingMemberships: isCancellingMemberships ??
          this.isCancellingMemberships,
      cancelOutcome: clearCancelOutcome
          ? null
          : (cancelOutcome ?? this.cancelOutcome),
      isRemovingAuthorization: isRemovingAuthorization ??
          this.isRemovingAuthorization,
      removeAuthorizationOutcome: clearRemoveAuthorizationOutcome
          ? null
          : (removeAuthorizationOutcome ??
              this.removeAuthorizationOutcome),
      isChargingCard: isChargingCard ?? this.isChargingCard,
      chargeCardSuccess:
          chargeCardSuccess ?? this.chargeCardSuccess,
      chargeCardError: clearChargeOutcome
          ? null
          : (chargeCardError ?? this.chargeCardError),
      isUpgrading: isUpgrading ?? this.isUpgrading,
      upgradeSuccess: upgradeSuccess ?? this.upgradeSuccess,
      upgradeError: clearUpgradeOutcome
          ? null
          : (upgradeError ?? this.upgradeError),
      isEnding: isEnding ?? this.isEnding,
      endSuccess: endSuccess ?? this.endSuccess,
      endError: clearEndOutcome
          ? null
          : (endError ?? this.endError),
      isCheckingIn: isCheckingIn ?? this.isCheckingIn,
      checkInResult: clearCheckInOutcome
          ? null
          : (checkInResult ?? this.checkInResult),
      checkInError: clearCheckInOutcome
          ? null
          : (checkInError ?? this.checkInError),
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
        isCancellingMemberships,
        cancelOutcome,
        isRemovingAuthorization,
        removeAuthorizationOutcome,
        isChargingCard,
        chargeCardSuccess,
        chargeCardError,
        isUpgrading,
        upgradeSuccess,
        upgradeError,
        isEnding,
        endSuccess,
        endError,
        isCheckingIn,
        checkInResult,
        checkInError,
        refreshToken,
      ];
}

class MemberDetailError extends MemberDetailState {
  final String message;
  final String memberId;

  /// The HTTP status when the failure was a server error (null for a
  /// transport / parse error). Lets the screen tell a "this id doesn't
  /// line up" 4xx (bounce a deep link to the members list) apart from a
  /// transient 5xx / network error (keep the retryable error view).
  final int? statusCode;

  const MemberDetailError(
    this.message, {
    required this.memberId,
    this.statusCode,
  });

  /// A 4xx — the member id doesn't resolve to a viewable member (unknown
  /// / malformed id, or a gym the caller can't see), as opposed to a
  /// transient 5xx / network failure.
  bool get isNotFound =>
      statusCode != null && statusCode! >= 400 && statusCode! < 500;

  @override
  List<Object?> get props => [message, memberId, statusCode];
}
