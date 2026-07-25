import 'package:equatable/equatable.dart';

import 'package:crm/features/check_in/data/models/check_in_error_code.dart';
import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/check_in/data/models/check_in_warning.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// The kiosk check-in lane's sub-view — the screen the member surface shows
/// inside `KioskScreen`, which replaces the admin workspace while kiosk is
/// active. Distinct from `KioskStatus`, the security runway.
enum KioskView {
  /// Idle rest state: title + QR placeholder + name search + signup.
  home,

  /// The chosen member's today-classes grid, ready to pick + check in.
  classPick,

  /// The member-facing SELF-SERVE SIGNUP lane. One arm only: its multi-step
  /// flow is a separate state machine behind `KioskSignupCubit`, not more
  /// [KioskView] values.
  signup,

  /// The check-in request is in flight (spinner).
  checkingIn,

  /// Recorded (or already checked in) — the retention glance.
  checkedIn,

  /// The kiosk gate rejected the check-in, or the call failed — the
  /// blame-free front-desk handoff.
  blocked,

  /// A new flow was attempted while the session can't start one (past the
  /// lockout mark) — a calm "kiosk is closing" message.
  closing,
}

/// Immutable state of the [KioskFlowCubit]: the current [view] plus everything
/// each view renders. [copyWith] keeps the nullable outcome fields by sentinel,
/// but an explicit `null` clears one — how a fresh failure drops a stale code.
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

  /// The occurrences the CHECK-IN FLOW may offer this member: today's, filtered
  /// to the check-in window, loaded per member and cleared on the way home.
  /// Never render this on the "Get the app" showcase — that slide has its own
  /// [showcaseClasses], and the two answer different questions.
  final List<EffectiveClassInstance> classes;
  final bool classesFailed;

  // ── Check-in outcome ──
  final CheckInResponse? checkInResult;
  final CheckInWarning? blockedReason;

  /// The class the member just tapped, carried so the glance can confirm WHICH
  /// class (the check-in response carries only a `class_id`).
  final String? selectedClassName;

  /// The check-in call itself failed (network / 5xx) — distinct from a gate
  /// rejection, which carries a [blockedReason].
  final bool checkInFailed;

  /// The backend's stable machine-readable rejection code off a FAILED call
  /// (the `code` sibling of `detail`), which picks the blocked screen's copy.
  /// Null when the failure carried none — the screen then shows its generic
  /// line. Only meaningful alongside [checkInFailed].
  final CheckInErrorCode? checkInErrorCode;

  // ── Retention glance ──
  /// The live points balance AFTER the just-awarded points. Null while loading
  /// or when the fetch failed — the tiles then show cost only. Distinct from
  /// [checkInResult]'s per-check-in points delta.
  final int? pointsBalance;

  /// The gym-wide reward catalog (active, cheapest-first, capped) — the
  /// glance's tiles and the "Earn rewards" slide. Empty when the gym has no
  /// rewards or the fetch failed.
  final List<RewardResponse> rewards;

  // ── Gym-wide showcase catalogues (fetched once at kiosk entry, surviving
  // goHome; an empty one omits its slide and dot) ──
  /// The gym's next few UPCOMING occurrences — the "Book classes" slide, and a
  /// SEPARATE list from the check-in flow's [classes] on purpose (the rule
  /// lives on `KioskFlowCubit._warmShowcaseClasses`).
  final List<EffectiveClassInstance> showcaseClasses;

  /// The head of this gym's OWN curated video feed — the "Watch videos" slide.
  final List<Video> videos;

  /// The gym's ordered main-rank ladder — the "Track rank" slide. Also empty
  /// when the gym has ranks switched off. Deliberately no member-rank field
  /// beside it: the slide is illustrative in every state (`KioskRankSlide`).
  final List<MainRank> rankLadder;

  /// The per-glance data fetch (rewards + balance) is in flight.
  final bool glanceLoading;

  /// Seconds left on the glance's hold ([kKioskGlanceHold], which starts AFTER
  /// the reveal's last beat). Drives the label + drain bar; 0 off the glance.
  final int glanceCountdown;

  // ── Flow-idle warning ──
  final bool idleWarningActive;
  final int idleCountdown;

  // ── "Get the app" modal ──
  /// Whether the "Get the app" overlay is open. While open it pauses the
  /// glance's auto-return and runs its OWN timer ([appModalCountdown]).
  final bool appModalOpen;

  /// Seconds left on the modal's auto-close; 0 when it is closed.
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
    this.showcaseClasses = const [],
    this.videos = const [],
    this.rankLadder = const [],
    this.glanceLoading = false,
    this.glanceCountdown = 0,
    this.idleWarningActive = false,
    this.idleCountdown = 0,
    this.appModalOpen = false,
    this.appModalCountdown = 0,
  });

  /// The idle rest state — every field cleared, so returning here abandons any
  /// in-progress draft (privacy: no half-entered name left on screen). It
  /// clears the gym-wide catalogues too; `KioskFlowCubit._freshHome` re-seeds
  /// them from its caches so the showcase never re-fetches.
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
    List<EffectiveClassInstance>? showcaseClasses,
    List<Video>? videos,
    List<MainRank>? rankLadder,
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
      showcaseClasses: showcaseClasses ?? this.showcaseClasses,
      videos: videos ?? this.videos,
      rankLadder: rankLadder ?? this.rankLadder,
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
        showcaseClasses,
        videos,
        rankLadder,
        glanceLoading,
        glanceCountdown,
        idleWarningActive,
        idleCountdown,
        appModalOpen,
        appModalCountdown,
      ];
}
