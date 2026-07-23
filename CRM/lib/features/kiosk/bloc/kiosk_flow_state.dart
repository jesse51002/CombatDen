import 'package:equatable/equatable.dart';

import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/check_in/data/models/check_in_warning.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// The kiosk check-in lane's sub-view — the screen the member surface is
/// currently showing INSIDE `KioskScreen` (which itself replaces the admin
/// workspace while kiosk is active). Distinct from the Phase B
/// `KioskStatus`, which is the security runway, not the flow.
enum KioskView {
  /// Idle rest state: title + QR placeholder + name search + signup.
  home,

  /// The chosen member's today-classes grid, ready to pick + check in.
  classPick,

  /// The check-in request is in flight (spinner).
  checkingIn,

  /// Recorded (or already-checked-in) — the Phase C2 glance stub.
  checkedIn,

  /// The kiosk gate rejected the check-in, or the call failed — the
  /// blame-free front-desk handoff.
  blocked,

  /// A new flow was attempted while the session can't start one (past the
  /// lockout mark) — a calm "kiosk is closing" message.
  closing,
}

/// Immutable state of the [KioskFlowCubit]. One flat state carries the current
/// [view] plus everything each view renders (search results, the chosen
/// member/occurrence outcome, the idle-warning countdown). Nullable outcome
/// fields ([selectedMember], [checkInResult], [blockedReason]) reset to null
/// only via [KioskFlowState.home]; [copyWith] never nulls them (sentinel).
class KioskFlowState extends Equatable {
  final KioskView view;

  // ── Name search (home) ──
  final String searchQuery;
  final List<MemberRow> searchResults;
  final bool searching;
  final bool searchFailed;

  // ── Class pick ──
  final MemberRow? selectedMember;
  final bool classesLoading;
  final List<EffectiveClassInstance> classes;
  final bool classesFailed;

  // ── Check-in outcome ──
  final CheckInResponse? checkInResult;
  final CheckInWarning? blockedReason;

  /// The check-in call itself failed (network / 5xx) — distinct from a gate
  /// rejection, which carries a [blockedReason].
  final bool checkInFailed;

  // ── Retention glance (Phase C2) ──
  /// The member's live points balance AFTER the just-awarded points, fetched
  /// on the glance. Null while loading OR when the billing fetch failed — the
  /// glance then degrades gracefully (no balance number, reward tiles show
  /// cost only). Distinct from [checkInResult]'s per-check-in points delta.
  final int? pointsBalance;

  /// The gym-wide reward catalog (active, cheapest-first, capped) shown as the
  /// glance's tiles. Cached once on the cubit and reused for every member;
  /// empty when the gym has no rewards (or the catalog fetch failed).
  final List<RewardResponse> rewards;

  /// The per-glance data fetch (rewards + balance) is in flight.
  final bool glanceLoading;

  /// Seconds left on the glance's 8-second auto-return to home. Drives the
  /// "Back to start in Ns" label + the drain bar. 0 off the glance.
  final int glanceCountdown;

  // ── Flow-idle warning ──
  final bool idleWarningActive;
  final int idleCountdown;

  const KioskFlowState({
    required this.view,
    this.searchQuery = '',
    this.searchResults = const [],
    this.searching = false,
    this.searchFailed = false,
    this.selectedMember,
    this.classesLoading = false,
    this.classes = const [],
    this.classesFailed = false,
    this.checkInResult,
    this.blockedReason,
    this.checkInFailed = false,
    this.pointsBalance,
    this.rewards = const [],
    this.glanceLoading = false,
    this.glanceCountdown = 0,
    this.idleWarningActive = false,
    this.idleCountdown = 0,
  });

  /// The idle rest state — every field cleared. Returning here abandons any
  /// in-progress draft (privacy: no half-entered name left on screen).
  const KioskFlowState.home() : this(view: KioskView.home);

  static const Object _keep = Object();

  KioskFlowState copyWith({
    KioskView? view,
    String? searchQuery,
    List<MemberRow>? searchResults,
    bool? searching,
    bool? searchFailed,
    Object? selectedMember = _keep,
    bool? classesLoading,
    List<EffectiveClassInstance>? classes,
    bool? classesFailed,
    Object? checkInResult = _keep,
    Object? blockedReason = _keep,
    bool? checkInFailed,
    Object? pointsBalance = _keep,
    List<RewardResponse>? rewards,
    bool? glanceLoading,
    int? glanceCountdown,
    bool? idleWarningActive,
    int? idleCountdown,
  }) {
    return KioskFlowState(
      view: view ?? this.view,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      searching: searching ?? this.searching,
      searchFailed: searchFailed ?? this.searchFailed,
      selectedMember: identical(selectedMember, _keep)
          ? this.selectedMember
          : selectedMember as MemberRow?,
      classesLoading: classesLoading ?? this.classesLoading,
      classes: classes ?? this.classes,
      classesFailed: classesFailed ?? this.classesFailed,
      checkInResult: identical(checkInResult, _keep)
          ? this.checkInResult
          : checkInResult as CheckInResponse?,
      blockedReason: identical(blockedReason, _keep)
          ? this.blockedReason
          : blockedReason as CheckInWarning?,
      checkInFailed: checkInFailed ?? this.checkInFailed,
      pointsBalance: identical(pointsBalance, _keep)
          ? this.pointsBalance
          : pointsBalance as int?,
      rewards: rewards ?? this.rewards,
      glanceLoading: glanceLoading ?? this.glanceLoading,
      glanceCountdown: glanceCountdown ?? this.glanceCountdown,
      idleWarningActive: idleWarningActive ?? this.idleWarningActive,
      idleCountdown: idleCountdown ?? this.idleCountdown,
    );
  }

  @override
  List<Object?> get props => [
        view,
        searchQuery,
        searchResults,
        searching,
        searchFailed,
        selectedMember,
        classesLoading,
        classes,
        classesFailed,
        checkInResult,
        blockedReason,
        checkInFailed,
        pointsBalance,
        rewards,
        glanceLoading,
        glanceCountdown,
        idleWarningActive,
        idleCountdown,
      ];
}
