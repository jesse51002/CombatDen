import 'package:equatable/equatable.dart';

import 'package:crm/features/check_in/data/models/check_in_error_code.dart';
import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/check_in/data/models/check_in_warning.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
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
/// fields ([selectedMember], [checkInResult], [blockedReason],
/// [checkInErrorCode]) reset to null only via [KioskFlowState.home];
/// [copyWith] never nulls them implicitly (sentinel) — an explicit `null`
/// argument does clear one, which is how a fresh failure drops a stale code.
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

  /// The name of the class the member just tapped, carried from the picked
  /// occurrence so the glance can CONFIRM which class they are checked into
  /// (the check-in response carries only a `class_id`). Null before a class is
  /// picked; cleared on the way home like every other per-member field.
  final String? selectedClassName;

  /// The check-in call itself failed (network / 5xx) — distinct from a gate
  /// rejection, which carries a [blockedReason].
  final bool checkInFailed;

  /// The backend's stable machine-readable rejection code off a FAILED call
  /// (the `code` sibling of `detail` — see [CheckInErrorCode]), which picks the
  /// blocked screen's copy. Null when the failure carried none: a network drop,
  /// a 5xx, or a foreign 4xx body — the screen then shows its generic line.
  /// Only meaningful alongside [checkInFailed].
  final CheckInErrorCode? checkInErrorCode;

  // ── Retention glance (Phase C2) ──
  /// The member's live points balance AFTER the just-awarded points, fetched
  /// on the glance. Null while loading OR when the billing fetch failed — the
  /// glance then degrades gracefully (no balance number, reward tiles show
  /// cost only). Distinct from [checkInResult]'s per-check-in points delta.
  final int? pointsBalance;

  /// The gym-wide reward catalog (active, cheapest-first, capped) shown as the
  /// glance's tiles and the "Earn rewards" showcase slide. Fetched ONCE at
  /// kiosk entry and reused for every member (it survives [goHome]); empty
  /// when the gym has no rewards, or when the catalog fetch failed.
  final List<RewardResponse> rewards;

  // ── Gym-wide showcase catalogues (fetched once at kiosk entry) ──
  /// The head of this gym's OWN curated video feed — the "Watch videos"
  /// showcase slide. Fetched once at kiosk entry and reused (it survives
  /// [goHome]); empty when the gym's feed is empty or the fetch failed, and
  /// the slide is then omitted rather than showing anything invented.
  final List<Video> videos;

  /// The gym's ordered main-rank ladder — the "Track rank" showcase slide.
  /// Fetched once at kiosk entry and reused (it survives [goHome]). EMPTY
  /// when the gym has ranks switched off, has configured none, or the fetch
  /// failed; the slide (and its dot) is then omitted.
  final List<MainRank> rankLadder;

  /// The checked-in member's current main-rank id, from the glance's member
  /// fetch — it tags the "You're here" rung on the rank slide. Null from the
  /// idle home (no member is known there), which simply leaves the ladder
  /// untagged rather than guessing a rung.
  final String? currentRankId;

  /// The per-glance data fetch (rewards + balance) is in flight.
  final bool glanceLoading;

  /// Seconds left on the glance's 8-second auto-return to home. Drives the
  /// "Back to start in Ns" label + the drain bar. 0 off the glance.
  final int glanceCountdown;

  // ── Flow-idle warning ──
  final bool idleWarningActive;
  final int idleCountdown;

  // ── "Get the app" modal (UX-5) ──
  /// Whether the member-facing "Get the app" modal is open — an overlay funnel
  /// opened from a glance tap or the home QR panel. While open it pauses the
  /// glance's auto-return and runs its OWN 60-second timer
  /// ([appModalCountdown]). Done clears it and reveals the view underneath
  /// (restarting the glance hold at full); the 60 seconds running out means
  /// nobody is there and returns home.
  final bool appModalOpen;

  /// Seconds left on the app modal's 60-second auto-close. Drives its "Back to
  /// start in Ns" label + drain bar. 0 when the modal is closed.
  final int appModalCountdown;

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
    this.selectedClassName,
    this.checkInFailed = false,
    this.checkInErrorCode,
    this.pointsBalance,
    this.rewards = const [],
    this.videos = const [],
    this.rankLadder = const [],
    this.currentRankId,
    this.glanceLoading = false,
    this.glanceCountdown = 0,
    this.idleWarningActive = false,
    this.idleCountdown = 0,
    this.appModalOpen = false,
    this.appModalCountdown = 0,
  });

  /// The idle rest state — every field cleared. Returning here abandons any
  /// in-progress draft (privacy: no half-entered name left on screen).
  ///
  /// It clears the gym-wide catalogues too, because it is a plain "everything
  /// off" constant. [KioskFlowCubit.goHome] re-seeds them from its entry-time
  /// caches, so the showcase never re-fetches on the way home — see
  /// `KioskFlowCubit._freshHome`.
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
    Object? selectedClassName = _keep,
    bool? checkInFailed,
    Object? checkInErrorCode = _keep,
    Object? pointsBalance = _keep,
    List<RewardResponse>? rewards,
    List<Video>? videos,
    List<MainRank>? rankLadder,
    Object? currentRankId = _keep,
    bool? glanceLoading,
    int? glanceCountdown,
    bool? idleWarningActive,
    int? idleCountdown,
    bool? appModalOpen,
    int? appModalCountdown,
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
      selectedClassName: identical(selectedClassName, _keep)
          ? this.selectedClassName
          : selectedClassName as String?,
      checkInFailed: checkInFailed ?? this.checkInFailed,
      checkInErrorCode: identical(checkInErrorCode, _keep)
          ? this.checkInErrorCode
          : checkInErrorCode as CheckInErrorCode?,
      pointsBalance: identical(pointsBalance, _keep)
          ? this.pointsBalance
          : pointsBalance as int?,
      rewards: rewards ?? this.rewards,
      videos: videos ?? this.videos,
      rankLadder: rankLadder ?? this.rankLadder,
      currentRankId: identical(currentRankId, _keep)
          ? this.currentRankId
          : currentRankId as String?,
      glanceLoading: glanceLoading ?? this.glanceLoading,
      glanceCountdown: glanceCountdown ?? this.glanceCountdown,
      idleWarningActive: idleWarningActive ?? this.idleWarningActive,
      idleCountdown: idleCountdown ?? this.idleCountdown,
      appModalOpen: appModalOpen ?? this.appModalOpen,
      appModalCountdown: appModalCountdown ?? this.appModalCountdown,
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
        selectedClassName,
        checkInFailed,
        checkInErrorCode,
        pointsBalance,
        rewards,
        videos,
        rankLadder,
        currentRankId,
        glanceLoading,
        glanceCountdown,
        idleWarningActive,
        idleCountdown,
        appModalOpen,
        appModalCountdown,
      ];
}
