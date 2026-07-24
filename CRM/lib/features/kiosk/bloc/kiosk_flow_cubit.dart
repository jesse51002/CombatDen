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

/// How many name matches the search shows — a short, scannable list.
const int kKioskSearchResultCount = 8;

/// Debounce before a keystroke fires the name-search fetch.
const Duration kKioskSearchDebounce = Duration(milliseconds: 300);

/// Inactivity on an in-progress flow page before the warning modal pops. Never
/// runs on the idle home screen (home is the rest state) NOR on the retention
/// glance (which has its own [kKioskGlanceHold]). Distinct from the
/// Phase B 12h runway.
const Duration kKioskIdleTimeout = Duration(minutes: 5);

/// The visible countdown on the idle warning before it abandons the draft and
/// returns to home. Confirmed 30s — this one line is the switch.
const Duration kKioskIdleCountdown = Duration(seconds: 30);

/// How long the post-check-in retention glance HOLDS once its last beat has
/// landed, before auto-returning to home so the next member gets a clean home.
/// A member can also leave early (Done / a tap anywhere). This is the glance's
/// OWN clock — it is not the 5-minute flow-idle guard (the flow has already
/// ended by the glance).
///
/// Ten seconds is the founder's number, and it is time to READ a finished
/// screen: it deliberately does NOT start on screen entry (see
/// [kKioskGlanceLastBeat]).
const Duration kKioskGlanceHold = Duration(seconds: 10);

/// When the glance's LAST beat lands — the streak + rewards cards, which
/// arrive together. The [kKioskGlanceHold] clock is waited out from here, not
/// from screen entry.
///
/// The reveal is a deliberate two-beat choreography (the confirmation centred
/// and alone for 1.5s, then a lift, then both cards), so a hold measured from
/// ENTRY would spend its opening seconds watching the screen assemble itself.
/// The hold is time to read something finished, so it starts when the last
/// thing arrives; the glance's total life is therefore this plus the ten, by
/// design. The full countdown value is shown from the first frame (the footer
/// never reads "0s" mid-reveal); only the decrementing starts late.
///
/// It must equal the last beat of `KioskRevealTimings` — the glance test
/// asserts exactly that, and also that the reward cascade inside that beat
/// finishes early enough to leave most of the hold on a settled screen. Under
/// reduced motion everything is on screen at once and the member simply gets
/// this much extra hold, which is the safe direction to err.
const Duration kKioskGlanceLastBeat = Duration(milliseconds: 2220);

/// The glance's 2x2 tile grid shows at most this many rewards (cheapest-first);
/// a gym with more rewards surfaces the nearest few, the rest live in the app.
const int kKioskGlanceRewardCount = 4;

/// How many of this gym's own videos the "Watch videos" showcase slide
/// shows — a two-card row. Only this many are fetched.
const int kKioskShowcaseVideoCount = 2;

/// How long the "Get the app" modal (UX-5) stays open before it auto-closes
/// back to home, so the next member gets a clean home. A member can also leave
/// early with Done — which returns them to the view underneath instead, see
/// [KioskFlowCubit.closeAppModal]. It is the modal's OWN clock — a plain
/// countdown that member interaction does NOT reset (unlike the 5-minute idle
/// guard); the modal is a self-dismissing overlay, not an in-progress draft.
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
    // The picked class's NAME rides along from here: the check-in response
    // carries only a `class_id`, and the glance has to confirm WHICH class the
    // member is now checked into.
    emit(state.copyWith(
      view: KioskView.checkingIn,
      selectedClassName: occ.className,
    ));
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
        // own hold clock (not the 5-min idle) governs the return home.
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
    try {
      final detail = await _memberRepo.getMemberDetail(member.memberId);
      balance = detail.retention.pointsBalance;
    } catch (e, st) {
      log('Kiosk points balance load failed', error: e, stackTrace: st);
    }
    if (isClosed || seq != _glanceSeq) return;
    emit(state.copyWith(
      rewards: rewards,
      pointsBalance: balance,
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

  /// Start the glance's 10-second hold — but only once the reveal's LAST beat
  /// has landed ([kKioskGlanceLastBeat]). The full countdown value is emitted
  /// immediately so the footer reads "Back to start in 10s" with a full drain
  /// bar from the first frame; what waits is the DECREMENT, so the reveal
  /// never eats the member's reading time. After the last beat one per-second
  /// countdown drives the visible timer and, at zero, returns home (mirrors
  /// the idle countdown).
  ///
  /// Both timers share [_glanceTimer], so every existing cancel site (goHome,
  /// openAppModal, close) still kills the auto-return whichever phase it is
  /// in — cancelling during the reveal simply means the periodic never starts.
  void _startGlanceReturn() {
    _glanceTimer?.cancel();
    emit(state.copyWith(glanceCountdown: kKioskGlanceHold.inSeconds));
    _glanceTimer = Timer(kKioskGlanceLastBeat, () {
      if (isClosed) return;
      _startGlanceCountdown();
    });
  }

  /// The hold itself — one per-second countdown that returns home at zero.
  /// Split out of [_startGlanceReturn] because closing the "Get the app" modal
  /// restarts the hold on a glance that has ALREADY finished revealing, and
  /// that path must not wait out [kKioskGlanceLastBeat] a second time.
  void _startGlanceCountdown() {
    _glanceTimer?.cancel();
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

  /// Give the glance its WHOLE hold back after the modal closes over it.
  ///
  /// The member spent their read-time inside the modal, so handing them the
  /// two seconds that happened to be left when they opened it would eject them
  /// mid-sentence. The countdown is reset to [kKioskGlanceHold] in full and
  /// starts draining immediately — the glance behind the modal is settled, so
  /// there is no reveal left to wait for (and the glance screen never
  /// re-mounts, so its choreography does not replay either).
  void _restartGlanceHold() {
    emit(state.copyWith(glanceCountdown: kKioskGlanceHold.inSeconds));
    _startGlanceCountdown();
  }

  // ── "Get the app" modal (UX-5) ──

  /// Open the member-facing "Get the app" modal — opened by a tap on the
  /// retention glance (the founder's UX-5 ruling: the glance tap now offers
  /// the app instead of ejecting home) or the home adopt strip's "Get it"
  /// affordance. Opening it PAUSES the glance's auto-return — in EITHER phase,
  /// the pre-hold reveal window or the running 10-second hold, since both ride
  /// the one [_glanceTimer] — and any flow-idle guard, and starts the modal's
  /// OWN 60-second auto-close. It is a pure informational overlay — it does
  /// NOT begin a member flow (no
  /// [KioskSessionCubit.beginFlow]) — so it never touches the grace-window
  /// bookkeeping. Idempotent while already open.
  ///
  /// The paused glance timer is not resumed on close, it is RESTARTED at full
  /// ([closeAppModal]) — the modal ate the member's reading time.
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
  ///
  /// **Expiry goes HOME, unlike Done.** Sixty seconds of no interaction means
  /// nobody is standing at the kiosk, and dropping back onto a glance would
  /// leave a member's name, streak and points on a shared iPad for the next
  /// person to read. So the timer running out is treated as "they walked away"
  /// and clears the surface, while Done — a deliberate press by someone still
  /// there — hands them back what they were looking at ([closeAppModal]).
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

  /// Close the modal (Done) and return to WHATEVER WAS UNDERNEATH IT.
  ///
  /// The modal is an overlay, so dismissing it reveals the view it opened over
  /// — the retention glance when it was opened by a glance tap, the idle home
  /// when it came from the home adopt strip's "Get it". It used to call
  /// [goHome] unconditionally, which ejected a member out of their own
  /// check-in result the moment they pressed Done (founder-reported bug).
  ///
  /// Returning to the glance RESTARTS its hold at full [kKioskGlanceHold]: the
  /// member spent their reading time in the modal, so they get the whole ten
  /// seconds again rather than the few that were left. The glance's reveal
  /// choreography does NOT replay — the screen stayed mounted behind the
  /// overlay, so only its countdown is restarted. Returning to home simply
  /// re-arms the 5-minute flow-idle guard the modal suppressed.
  ///
  /// Idempotent when the modal isn't open, and it always cancels the modal's
  /// own 60-second timer so no late tick can fire a [goHome] afterwards.
  void closeAppModal() {
    if (!state.appModalOpen) return;
    _appModalTimer?.cancel();
    emit(state.copyWith(appModalOpen: false, appModalCountdown: 0));
    if (state.view == KioskView.checkedIn) {
      _restartGlanceHold();
    } else {
      _syncIdleTimer();
    }
  }

  // ── Return to home (Done / cancel / idle timeout) ──

  /// Abandon any in-progress draft and return to the idle home screen. Ends
  /// the flow if one was started; cancels the search + idle timers.
  ///
  /// This is the ONE abandon path — the glance's Done, the idle timeout, the
  /// app modal's EXPIRY (never its Done, which returns to the view underneath)
  /// and the class-pick escape ("Not Marcus?", `KioskEscapeFoot`) all come
  /// through here. Never hand-roll another: dropping [_endFlowIfStarted]
  /// leaks the session's in-progress flow count and the kiosk then never signs
  /// itself out at the T+11h45 lockout, and dropping the sequence bumps lets a
  /// late fetch paint the previous member's data over the next person's home.
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
    // The retention glance is governed by its own hold clock, never the
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
