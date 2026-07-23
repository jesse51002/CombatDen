import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/check_in/data/models/check_in_error_code.dart';
import 'package:crm/features/check_in/data/models/check_in_request.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members/data/gym_content_repository.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/occurrence_windows.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

/// A member must type at least this many characters before a name search runs.
const int kKioskSearchMinChars = 2;

/// How many name matches the search shows (the mockup lists a short list).
const int kKioskSearchResultCount = 8;

/// Debounce before a keystroke fires the name-search fetch.
const Duration kKioskSearchDebounce = Duration(milliseconds: 300);

/// Inactivity on an in-progress flow page before the warning modal pops. Never
/// runs on the idle home screen (home is the rest state) NOR on the retention
/// glance (which has its own [kKioskGlanceAutoReturn]). Distinct from the
/// Phase B 12h runway.
const Duration kKioskIdleTimeout = Duration(minutes: 5);

/// The visible countdown on the idle warning before it abandons the draft and
/// returns to home. Confirmed 30s — this one line is the switch.
const Duration kKioskIdleCountdown = Duration(seconds: 30);

/// How long the post-check-in retention glance stays up before auto-returning
/// to home, so the next member gets a clean home. A member can also leave early
/// (Done / a tap anywhere). This is the glance's OWN clock — it is not the
/// 5-minute flow-idle guard (the flow has already ended by the glance).
const Duration kKioskGlanceAutoReturn = Duration(seconds: 8);

/// The glance's 2x2 tile grid shows at most this many rewards (cheapest-first);
/// a gym with more rewards surfaces the nearest few, the rest live in the app.
const int kKioskGlanceRewardCount = 4;

/// How many of this gym's own videos the "Watch videos" showcase slide shows
/// (mockup `.vc-grid` is a two-card row). Only this many are fetched.
const int kKioskShowcaseVideoCount = 2;

/// How long the "Get the CombatDen App" modal (UX-5) stays open before it
/// auto-closes back to home, so the next member gets a clean home. A member can
/// also leave early with Done. It is the modal's OWN clock — a plain countdown
/// that member interaction does NOT reset (unlike the 5-minute idle guard); the
/// modal is a self-dismissing overlay, not an in-progress draft.
const Duration kKioskAppModalTimeout = Duration(seconds: 60);

/// Drives the kiosk check-in lane's internal navigation: the current
/// [KioskView], the in-progress member/occurrence draft, live name search, the
/// `is_member: true` check-in, and the 5-minute flow-idle guard.
///
/// It sits BELOW the app-root [KioskSessionCubit] (the security runway) and
/// leans on it for three things: gate a new flow on
/// [KioskSessionState.canStartFlow], mark a started flow with
/// [KioskSessionCubit.beginFlow], and clear it with
/// [KioskSessionCubit.endFlow] — so a lockout landing mid-check-in grants the
/// grace window. Any back / cancel / idle-timeout returns to home and abandons
/// the draft.
class KioskFlowCubit extends Cubit<KioskFlowState> {
  KioskFlowCubit({
    required MembersListRepository membersRepository,
    required ScheduleRepository scheduleRepository,
    required MemberRepository memberRepository,
    required RewardsRepository rewardsRepository,
    required GymContentRepository gymContentRepository,
    required RanksRepository ranksRepository,
    required KioskSessionCubit session,
    required String gymId,
    DateTime Function() now = DateTime.now,
  })  : _membersRepo = membersRepository,
        _scheduleRepo = scheduleRepository,
        _memberRepo = memberRepository,
        _rewardsRepo = rewardsRepository,
        _contentRepo = gymContentRepository,
        _ranksRepo = ranksRepository,
        _session = session,
        _gymId = gymId,
        _now = now,
        super(const KioskFlowState.home()) {
    // Warm the three GYM-WIDE catalogues once, here at kiosk entry, and cache
    // them for the whole session: they are identical for every member, and the
    // member-facing screens that render them (the glance, the "Get the app"
    // showcase) must open instantly — the modal in particular fires no fetch
    // of its own. Each is independent and each failure is non-fatal: the
    // glance degrades to points-only, and a showcase slide with no data is
    // simply omitted rather than showing an error on a member-facing screen.
    unawaited(_warmRewards());
    unawaited(_warmVideos());
    unawaited(_warmRankLadder());
  }

  final MembersListRepository _membersRepo;
  final ScheduleRepository _scheduleRepo;
  final MemberRepository _memberRepo;
  final RewardsRepository _rewardsRepo;
  final GymContentRepository _contentRepo;
  final RanksRepository _ranksRepo;
  final KioskSessionCubit _session;
  final String _gymId;
  final DateTime Function() _now;

  /// Backend `occurrence_date` is a bare gym-local `YYYY-MM-DD` (mirrors
  /// `ScheduleRepository`).
  static final DateFormat _dateParam = DateFormat('yyyy-MM-dd');

  Timer? _searchDebounce;
  Timer? _idleTimer;
  Timer? _countdownTimer;
  Timer? _glanceTimer;
  Timer? _appModalTimer;
  int _searchSeq = 0;
  int _classesSeq = 0;
  int _glanceSeq = 0;

  /// The gym-wide reward catalog, fetched ONCE and reused for every member's
  /// glance. Null until the first successful fetch; a failed fetch leaves it
  /// null so a later glance retries. [_rewardsInFlight] dedups concurrent
  /// fetches (the eager warm + a fast first check-in).
  List<RewardResponse>? _rewardsCache;
  Future<List<RewardResponse>>? _rewardsInFlight;

  /// This gym's own curated video feed head + its main-rank ladder — the other
  /// two gym-wide catalogues, likewise fetched once at entry. Unlike the
  /// rewards catalog nothing re-attempts these mid-session: they feed showcase
  /// slides only, and an absent slide is the designed degradation. They are
  /// held here (not only on the state) so [goHome] can re-seed a fresh home
  /// without re-fetching.
  List<Video> _videosCache = const [];
  List<MainRank> _rankLadderCache = const [];

  /// Whether this flow has told the session it started (so end is balanced —
  /// exactly one [KioskSessionCubit.endFlow] per [KioskSessionCubit.beginFlow]).
  bool _flowStarted = false;

  // ── Name search (home) ──

  /// Debounced live name search. Reflects the query immediately (for the idle
  /// guard + a stale-response check), then fetches after [kKioskSearchDebounce].
  void search(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < kKioskSearchMinChars) {
      _searchSeq++; // invalidate any in-flight fetch
      emit(state.copyWith(
        searchQuery: query,
        searchResults: const [],
        searching: false,
        searchFailed: false,
      ));
    } else {
      emit(state.copyWith(searchQuery: query));
      _searchDebounce = Timer(kKioskSearchDebounce, () => _runSearch(trimmed));
    }
    _syncIdleTimer();
  }

  Future<void> _runSearch(String query) async {
    final seq = ++_searchSeq;
    emit(state.copyWith(searching: true, searchFailed: false));
    try {
      final resp = await _membersRepo.getMembersList(
        CrmMembersListRequest(
          gymId: _gymId,
          view: MembersListView.all,
          filters: MembersListFilters(name: query),
          startIndex: 0,
          count: kKioskSearchResultCount,
        ),
      );
      if (isClosed || seq != _searchSeq) return;
      emit(state.copyWith(searching: false, searchResults: resp.data));
    } catch (e, st) {
      log('Kiosk name search failed', error: e, stackTrace: st);
      if (isClosed || seq != _searchSeq) return;
      emit(state.copyWith(
        searching: false,
        searchResults: const [],
        searchFailed: true,
      ));
    }
  }

  // ── Member → class pick ──

  /// Advance to the class pick for [member] — but only while the session can
  /// start a flow. Past the lockout mark, show the calm closing message
  /// instead and never begin the flow.
  void selectMember(MemberRow member) {
    registerActivity();
    if (!_session.state.canStartFlow) {
      emit(state.copyWith(view: KioskView.closing));
      _syncIdleTimer();
      return;
    }
    _startFlow();
    final seq = ++_classesSeq;
    emit(state.copyWith(
      view: KioskView.classPick,
      selectedMember: member,
      classesLoading: true,
      classes: const [],
      classesFailed: false,
    ));
    _syncIdleTimer();
    unawaited(_loadClasses(seq));
  }

  Future<void> _loadClasses(int seq) async {
    final n = _now();
    final today = DateTime(n.year, n.month, n.day);
    try {
      final all =
          await _scheduleRepo.listEffectiveInstances(_gymId, today, today);
      if (isClosed || seq != _classesSeq) return;
      final now = _now();
      // Genuinely checkinable RIGHT NOW: in-session or starting within the 2h
      // early window (occurrenceCheckInOpen), AND not already ended — so this
      // morning's finished classes are dropped instead of being offered at
      // 6pm (the backend would silently accept a past occurrence). Kiosk-local:
      // the tighter end-bound lives here, not in the shared predicate the staff
      // check-in dialog reuses. Ordered current/soonest first — ascending start
      // instant puts an in-session class before an upcoming one.
      final open = all
          .where((i) =>
              !i.isCancelled &&
              occurrenceCheckInOpen(i.occurredAt, now) &&
              occurrenceEnd(i.occurredAt, i.resolvedDurationMinutes)
                  .isAfter(now))
          .toList()
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      emit(state.copyWith(classesLoading: false, classes: open));
    } catch (e, st) {
      log('Kiosk class load failed', error: e, stackTrace: st);
      if (isClosed || seq != _classesSeq) return;
      emit(state.copyWith(classesLoading: false, classesFailed: true));
    }
  }

  // ── Record the check-in ──

  /// Record the member into [occ] via the kiosk gate (`is_member: true`). A
  /// recorded or already-checked-in result (a non-null `log_id`) hands off to
  /// the glance stub; a gate rejection (`skip_reason`) or a failed call routes
  /// to the blame-free blocked screen — a failure carrying its reason as the
  /// backend's [CheckInErrorCode]. Either terminal ends the flow.
  Future<void> selectClass(EffectiveClassInstance occ) async {
    registerActivity();
    final member = state.selectedMember;
    if (member == null || state.view == KioskView.checkingIn) return;
    // Guard the async check-in with the class-flow seq (bumped by goHome /
    // selectMember): a response arriving after the member walked away must not
    // emit the prior member's glance/blocked over the next person. Mirrors the
    // stale-drop the search / class-load / glance fetches already do.
    final seq = _classesSeq;
    emit(state.copyWith(view: KioskView.checkingIn));
    _syncIdleTimer();
    try {
      final resp = await _memberRepo.checkInMember(
        CheckInRequest(
          memberId: member.memberId,
          gymId: _gymId,
          classId: occ.classId,
          occurrenceDate: _dateParam.format(occ.originalDate),
          occurrenceTime: occ.originalTime,
          isMember: true,
        ),
      );
      if (isClosed || seq != _classesSeq) return;
      _endFlowIfStarted();
      if (resp.logId == null) {
        emit(state.copyWith(
          view: KioskView.blocked,
          blockedReason: resp.skipReason,
        ));
        _syncIdleTimer();
      } else {
        // The retention glance: render the streak + earned points from the
        // response immediately, then fetch the balance + reward catalog. Its
        // own 8s clock (not the 5-min idle) governs the return home.
        emit(state.copyWith(
          view: KioskView.checkedIn,
          checkInResult: resp,
          pointsBalance: null,
          glanceLoading: true,
        ));
        _syncIdleTimer();
        _startGlanceReturn();
        unawaited(_loadGlanceData(member));
      }
    } catch (e, st) {
      log('Kiosk check-in failed', error: e, stackTrace: st);
      if (isClosed || seq != _classesSeq) return;
      _endFlowIfStarted();
      emit(state.copyWith(
        view: KioskView.blocked,
        checkInFailed: true,
        // The backend's stable rejection `code` (the sibling of `detail`) is
        // what the blocked screen switches on — NEVER the `detail` prose,
        // which is free to be reworded. A non-[ServerException] failure (a
        // network drop) or a body without a usable `code` passes null
        // explicitly, clearing any prior code so the screen falls back to its
        // generic line rather than inheriting the last member's reason.
        checkInErrorCode: e is ServerException
            ? CheckInErrorCode.fromErrorBody(e.data)
            : null,
      ));
      _syncIdleTimer();
    }
  }

  // ── Retention glance (data + auto-return) ──

  /// Fetch the glance's per-member data: the cached reward catalog + the
  /// member's live points balance (AFTER the just-awarded points). A
  /// [_glanceSeq] guard drops a stale result if the member has already left.
  /// Either fetch failing is non-fatal — the glance still shows the streak +
  /// earned points from the check-in response; a null [pointsBalance] degrades
  /// the tiles to cost-only, empty [rewards] to a points-only panel.
  Future<void> _loadGlanceData(MemberRow member) async {
    final seq = ++_glanceSeq;
    final rewards = await _ensureRewards();
    int? balance;
    String? rankId;
    try {
      final detail = await _memberRepo.getMemberDetail(member.memberId);
      balance = detail.retention.pointsBalance;
      // Also the "You're here" rung on the rank showcase slide — the same
      // fetch already pays for it, so no extra call.
      rankId = detail.rank?.rankId;
    } catch (e, st) {
      log('Kiosk points balance load failed', error: e, stackTrace: st);
    }
    if (isClosed || seq != _glanceSeq) return;
    emit(state.copyWith(
      rewards: rewards,
      pointsBalance: balance,
      currentRankId: rankId,
      glanceLoading: false,
    ));
  }

  /// The gym-wide reward catalog, fetched once and cached. Concurrent callers
  /// (the eager warm + a fast first glance) share the one in-flight future.
  Future<List<RewardResponse>> _ensureRewards() {
    final cached = _rewardsCache;
    if (cached != null) return Future.value(cached);
    return _rewardsInFlight ??= _fetchRewards();
  }

  Future<List<RewardResponse>> _fetchRewards() async {
    try {
      final all = await _rewardsRepo.listRewards(_gymId);
      final tiles = (all.where((r) => r.isActive).toList()
            ..sort((a, b) => a.pointCost.compareTo(b.pointCost)))
          .take(kKioskGlanceRewardCount)
          .toList();
      _rewardsCache = tiles; // cache successes; a failure stays uncached (retry)
      return tiles;
    } catch (e, st) {
      log('Kiosk rewards load failed', error: e, stackTrace: st);
      return const [];
    } finally {
      _rewardsInFlight = null;
    }
  }

  // ── Gym-wide showcase catalogues (warmed once at kiosk entry) ──

  /// Publish the warmed reward catalog onto the state, so the "Get the app"
  /// modal can show this gym's real rewards from the IDLE HOME too — not only
  /// after a check-in has populated the glance.
  Future<void> _warmRewards() async {
    final rewards = await _ensureRewards();
    if (isClosed || rewards.isEmpty) return;
    emit(state.copyWith(rewards: rewards));
  }

  /// The head of THIS gym's own curated feed (`GET /gyms/{id}/videos`) — the
  /// only per-gym feed the CRM can read. Deliberately not `selectedGym.detail`:
  /// that showcase belongs to a DEFAULT content gym, so rendering it here would
  /// put another gym's videos on a member-facing screen.
  Future<void> _warmVideos() async {
    try {
      final page = await _contentRepo.fetchVideos(
        _gymId,
        limit: kKioskShowcaseVideoCount,
      );
      if (isClosed) return;
      _videosCache = page.videos;
      if (page.videos.isEmpty) return;
      emit(state.copyWith(videos: page.videos));
    } catch (e, st) {
      // Non-fatal: the slide is omitted, never an error on a member screen.
      log('Kiosk video feed load failed', error: e, stackTrace: st);
    }
  }

  /// The gym's main-rank ladder — but only when the gym actually runs ranks.
  /// The enabled flag is a separate gym setting from the ladder rows, so a gym
  /// that configured belts and then switched ranks off must NOT see them; both
  /// reads happen here, once, and either falling short leaves the ladder empty
  /// (the slide and its dot are then omitted).
  Future<void> _warmRankLadder() async {
    try {
      final enabled = await _ranksRepo.getRankEnabled(_gymId);
      if (isClosed || !enabled.isRankEnabled) return;
      final ladder = await _ranksRepo.listRanks(_gymId);
      if (isClosed) return;
      _rankLadderCache = ladder.ranks;
      if (ladder.ranks.isEmpty) return;
      emit(state.copyWith(rankLadder: ladder.ranks));
    } catch (e, st) {
      // Non-fatal: the slide is omitted, never an error on a member screen.
      log('Kiosk rank ladder load failed', error: e, stackTrace: st);
    }
  }

  /// A fresh idle home that KEEPS the gym-wide catalogues (rewards, videos,
  /// rank ladder) — they are identical for every member and were paid for once
  /// at entry — while dropping every per-member field the plain
  /// [KioskFlowState.home] constant clears.
  KioskFlowState get _freshHome => const KioskFlowState.home().copyWith(
        rewards: _rewardsCache ?? const [],
        videos: _videosCache,
        rankLadder: _rankLadderCache,
      );

  /// Start the glance's 8-second auto-return. One per-second countdown drives
  /// the visible timer and, at zero, returns home (mirrors the idle countdown).
  void _startGlanceReturn() {
    _glanceTimer?.cancel();
    emit(state.copyWith(glanceCountdown: kKioskGlanceAutoReturn.inSeconds));
    _glanceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      final next = state.glanceCountdown - 1;
      if (next <= 0) {
        _glanceTimer?.cancel();
        goHome();
      } else {
        emit(state.copyWith(glanceCountdown: next));
      }
    });
  }

  // ── "Get the app" modal (UX-5) ──

  /// Open the member-facing "Get the CombatDen App" modal — opened by a tap on
  /// the retention glance (the founder's UX-5 ruling: the glance tap now offers
  /// the app instead of ejecting home) or the home QR panel's "Get it"
  /// affordance. Opening it PAUSES the glance's 8-second auto-return and any
  /// flow-idle guard, and starts the modal's OWN 60-second auto-close. It is a
  /// pure informational overlay — it does NOT begin a member flow (no
  /// [KioskSessionCubit.beginFlow]) — so it never touches the grace-window
  /// bookkeeping. Idempotent while already open.
  void openAppModal() {
    if (state.appModalOpen) return;
    // Pause the glance auto-return + suppress the idle guard: the modal's own
    // 60s clock is the sole timer while it is up.
    _glanceTimer?.cancel();
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    emit(state.copyWith(
      appModalOpen: true,
      appModalCountdown: kKioskAppModalTimeout.inSeconds,
      idleWarningActive: false,
      idleCountdown: 0,
    ));
    _startAppModalTimer();
  }

  /// The modal's 60-second auto-close. One per-second countdown drives the
  /// visible timer and, at zero, returns home (mirrors the glance/idle timers).
  void _startAppModalTimer() {
    _appModalTimer?.cancel();
    _appModalTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      final next = state.appModalCountdown - 1;
      if (next <= 0) {
        _appModalTimer?.cancel();
        goHome();
      } else {
        emit(state.copyWith(appModalCountdown: next));
      }
    });
  }

  /// Close the modal (Done) and return to a fresh home for the next member.
  void closeAppModal() => goHome();

  // ── Return to home (Done / cancel / idle timeout) ──

  /// Abandon any in-progress draft and return to the idle home screen. Ends
  /// the flow if one was started; cancels the search + idle timers.
  void goHome() {
    _searchDebounce?.cancel();
    _glanceTimer?.cancel();
    _appModalTimer?.cancel();
    _searchSeq++;
    _classesSeq++;
    _glanceSeq++; // drop any in-flight glance fetch
    _endFlowIfStarted();
    emit(_freshHome);
    _syncIdleTimer();
  }

  // ── Flow-idle guard ──

  /// Any member interaction: dismiss the idle warning if showing and reset the
  /// 5-minute clock. Wired to a pointer listener over the whole flow surface
  /// AND called by the interactive methods above.
  void registerActivity() {
    if (state.idleWarningActive) {
      emit(state.copyWith(idleWarningActive: false, idleCountdown: 0));
    }
    _syncIdleTimer();
  }

  /// A flow is "engaged" (the idle guard runs) whenever the member has left the
  /// idle rest state — past home, or typing a name into home's search.
  bool get _engaged =>
      state.view != KioskView.home || state.searchQuery.trim().isNotEmpty;

  void _syncIdleTimer() {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    // The retention glance is governed by its own 8s auto-return, never the
    // 5-minute flow-idle guard (the flow has already ended by then).
    if (state.view == KioskView.checkedIn) return;
    // The "Get the app" modal runs its own 60s clock — suppress the idle guard
    // beneath it (it can sit over an engaged home draft).
    if (state.appModalOpen) return;
    if (_engaged && !state.idleWarningActive) {
      _idleTimer = Timer(kKioskIdleTimeout, _onIdle);
    }
  }

  void _onIdle() {
    if (isClosed || !_engaged) return;
    emit(state.copyWith(
      idleWarningActive: true,
      idleCountdown: kKioskIdleCountdown.inSeconds,
    ));
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      final next = state.idleCountdown - 1;
      if (next <= 0) {
        _countdownTimer?.cancel();
        goHome();
      } else {
        emit(state.copyWith(idleCountdown: next));
      }
    });
  }

  // ── Session flow accounting (grace-window bookkeeping) ──

  void _startFlow() {
    if (_flowStarted) return;
    _flowStarted = true;
    _session.beginFlow();
  }

  void _endFlowIfStarted() {
    if (!_flowStarted) return;
    _flowStarted = false;
    _session.endFlow();
  }

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    _glanceTimer?.cancel();
    _appModalTimer?.cancel();
    // Balance a mid-flow teardown: without this the session's flowCount stays
    // incremented (endFlow is a pure in-memory decrement — safe post-close).
    _endFlowIfStarted();
    return super.close();
  }
}
