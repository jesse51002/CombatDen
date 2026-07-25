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
/// runs on the idle home nor the glance (its own [kKioskGlanceHold]).
const Duration kKioskIdleTimeout = Duration(minutes: 5);

/// The visible countdown on the idle warning before it abandons the draft and
/// returns home.
const Duration kKioskIdleCountdown = Duration(seconds: 30);

/// How long the post-check-in glance HOLDS once its last beat has landed
/// ([kKioskGlanceLastBeat]) before auto-returning home. The founder's number,
/// and it is time to READ a finished screen — not the flow-idle guard.
const Duration kKioskGlanceHold = Duration(seconds: 10);

/// When the glance's LAST beat lands. [kKioskGlanceHold] is waited out from
/// HERE, not from screen entry, so the reveal never spends the member's reading
/// time assembling the screen. Must equal the last beat of
/// `KioskRevealTimings` — the glance test asserts exactly that.
const Duration kKioskGlanceLastBeat = Duration(milliseconds: 2220);

/// The glance's 2x2 tile grid shows at most this many rewards (cheapest-first).
const int kKioskGlanceRewardCount = 4;

/// How many of this gym's own videos the "Watch videos" slide shows.
const int kKioskShowcaseVideoCount = 2;

/// How far ahead the "Book classes" showcase slide looks, in days from today.
/// Seven is the smallest range that CANNOT go empty by time of day on a weekly
/// schedule — a today-only range empties the slide every evening.
const int kKioskShowcaseClassDays = 7;

/// How many upcoming occurrences the "Book classes" slide shows.
const int kKioskShowcaseClassCount = 2;

/// How long the "Get the app" modal stays open before auto-closing home. Its
/// OWN clock, which member interaction does NOT reset (unlike the idle guard):
/// a self-dismissing overlay, not an in-progress draft.
const Duration kKioskAppModalTimeout = Duration(seconds: 60);

/// Drives the kiosk check-in lane's internal navigation: the current
/// [KioskView], the in-progress member/occurrence draft, live name search, the
/// `is_member: true` check-in, and the flow-idle guard. It sits below the
/// app-root [KioskSessionCubit] (the security runway), gating each new flow on
/// [KioskSessionState.canStartFlow] and bracketing it with
/// [KioskSessionCubit.beginFlow] / [KioskSessionCubit.endFlow]. Any back /
/// cancel / idle-timeout returns home and abandons the draft.
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
    // Warm the four GYM-WIDE catalogues once and cache them for the session:
    // identical for every member, and the screens rendering them must open
    // instantly. Each failure is deliberately non-fatal — the glance degrades
    // to points-only, a dataless slide is omitted, never an error on a member
    // screen.
    unawaited(_warmRewards());
    unawaited(_warmShowcaseClasses());
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

  /// Backend `occurrence_date` is a bare gym-local `YYYY-MM-DD`.
  static final DateFormat _dateParam = DateFormat('yyyy-MM-dd');

  Timer? _searchDebounce;
  Timer? _idleTimer;
  Timer? _countdownTimer;
  Timer? _glanceTimer;
  Timer? _appModalTimer;
  int _searchSeq = 0;
  int _classesSeq = 0;
  int _glanceSeq = 0;

  /// The gym-wide reward catalog, fetched ONCE and reused for every glance. A
  /// failed fetch leaves it null so a later glance retries; [_rewardsInFlight]
  /// dedups concurrent fetches (the eager warm + a fast first check-in).
  List<RewardResponse>? _rewardsCache;
  Future<List<RewardResponse>>? _rewardsInFlight;

  /// The other three gym-wide catalogues, fetched once at entry and never
  /// re-attempted (an absent slide is the designed degradation). Held here, not
  /// only on the state, so [goHome] re-seeds home without re-fetching.
  /// [_showcaseClassesCache] is NOT the check-in flow's class list — see
  /// [_warmShowcaseClasses].
  List<EffectiveClassInstance> _showcaseClassesCache = const [];
  List<Video> _videosCache = const [];
  List<MainRank> _rankLadderCache = const [];

  /// Whether this flow told the session it started, so exactly one
  /// [KioskSessionCubit.endFlow] balances each [KioskSessionCubit.beginFlow].
  bool _flowStarted = false;

  // ── Name search (home) ──

  /// Debounced live name search. Reflects the query immediately (for the idle
  /// guard + a stale-response check), then fetches after the debounce.
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
  /// start a flow. Past the lockout mark, show the calm closing message and
  /// never begin the flow.
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

  /// Open the member-facing SELF-SERVE SIGNUP lane, gated on the session like
  /// [selectMember]. It deliberately does NOT call [_startFlow]: that lane owns
  /// its own `beginFlow` latch, and double-counting in-progress flows would
  /// stop the kiosk ever signing itself out at lockout.
  void startSignup() {
    registerActivity();
    if (!_session.state.canStartFlow) {
      emit(state.copyWith(view: KioskView.closing));
      _syncIdleTimer();
      return;
    }
    emit(state.copyWith(view: KioskView.signup));
    _syncIdleTimer();
  }

  /// The CHECK-IN flow's class list: TODAY's occurrences, narrowed to the ones
  /// this member can check into right now. Read fresh per member, never from
  /// the showcase cache (see [_warmShowcaseClasses]).
  Future<void> _loadClasses(int seq) async {
    final n = _now();
    final today = DateTime(n.year, n.month, n.day);
    try {
      final all =
          await _scheduleRepo.listEffectiveInstances(_gymId, today, today);
      if (isClosed || seq != _classesSeq) return;
      final now = _now();
      // Checkinable RIGHT NOW: in session or inside the 2h early window, AND
      // not already ended — so this morning's finished classes aren't offered
      // at 6pm (the backend would silently accept a past occurrence). That
      // tighter end-bound is kiosk-local, not in the shared predicate.
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
  /// non-null `log_id` hands off to the glance; a rejection (`skip_reason`) or
  /// a failed call routes to the blocked screen. Either terminal ends the flow.
  Future<void> selectClass(EffectiveClassInstance occ) async {
    registerActivity();
    final member = state.selectedMember;
    if (member == null || state.view == KioskView.checkingIn) return;
    // The class-flow seq (bumped by goHome / selectMember) stops a response
    // arriving after the member walked away painting over the next person.
    final seq = _classesSeq;
    // The picked class's NAME rides along: the response carries only a
    // `class_id`, and the glance must confirm WHICH class.
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
        // Render the streak + earned points from the response immediately,
        // then fetch the balance + reward catalog.
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
        // The blocked screen switches on the backend's stable `code`, never
        // the `detail` prose, which is free to be reworded. A failure without
        // one passes null explicitly, so the screen shows its generic line
        // instead of inheriting the last member's reason.
        checkInErrorCode: e is ServerException
            ? CheckInErrorCode.fromErrorBody(e.data)
            : null,
      ));
      _syncIdleTimer();
    }
  }

  // ── Retention glance (data + auto-return) ──

  /// Fetch the glance's per-member data: the cached reward catalog + the live
  /// points balance (AFTER the just-awarded points). [_glanceSeq] drops a stale
  /// result if the member already left; either fetch failing is non-fatal.
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

  /// The cached catalog, or the one shared in-flight fetch.
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

  /// Publish the warmed catalog onto the state, so the "Get the app" modal
  /// shows real rewards from the IDLE HOME too, not only after a check-in.
  Future<void> _warmRewards() async {
    final rewards = await _ensureRewards();
    if (isClosed || rewards.isEmpty) return;
    emit(state.copyWith(rewards: rewards));
  }

  /// The gym's next few UPCOMING occurrences — the "Book classes" slide's own
  /// list, read ONCE at entry over `[today, today + N days]`.
  ///
  /// A SECOND, separate class list on purpose: never collapse it into
  /// [_loadClasses], whose check-in-window filter would empty this marketing
  /// slide every evening. This one looks FORWARD — not yet started, soonest
  /// first, capped — so every row is genuinely bookable, which is what the
  /// inert Book pill beside it depicts.
  Future<void> _warmShowcaseClasses() async {
    final n = _now();
    final today = DateTime(n.year, n.month, n.day);
    try {
      final all = await _scheduleRepo.listEffectiveInstances(
        _gymId,
        today,
        // Calendar arithmetic (not a Duration) so a DST shift inside the window
        // can't land the end date a day short.
        DateTime(n.year, n.month, n.day + kKioskShowcaseClassDays),
      );
      if (isClosed) return;
      final now = _now();
      final upcoming = (all
              .where((i) => !i.isCancelled && i.occurredAt.isAfter(now))
              .toList()
            ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt)))
          .take(kKioskShowcaseClassCount)
          .toList();
      _showcaseClassesCache = upcoming;
      if (upcoming.isEmpty) return;
      emit(state.copyWith(showcaseClasses: upcoming));
    } catch (e, st) {
      log('Kiosk showcase class load failed', error: e, stackTrace: st);
    }
  }

  /// The head of THIS gym's own curated feed. Deliberately not
  /// `selectedGym.detail`: that showcase belongs to a DEFAULT content gym, so
  /// it would put another gym's videos on a member-facing screen.
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
      log('Kiosk video feed load failed', error: e, stackTrace: st);
    }
  }

  /// The gym's main-rank ladder — but only when the gym actually runs ranks:
  /// the enabled flag is a separate setting from the ladder rows, so a gym that
  /// configured belts then switched ranks off must NOT see them.
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
      log('Kiosk rank ladder load failed', error: e, stackTrace: st);
    }
  }

  /// A fresh idle home that KEEPS the gym-wide catalogues (paid for once at
  /// entry) while dropping every per-member field [KioskFlowState.home] clears.
  /// The class list re-seeded here is the SHOWCASE's, never the check-in
  /// flow's, which is per-member.
  KioskFlowState get _freshHome => const KioskFlowState.home().copyWith(
        rewards: _rewardsCache ?? const [],
        showcaseClasses: _showcaseClassesCache,
        videos: _videosCache,
        rankLadder: _rankLadderCache,
      );

  /// Drop showcase occurrences that have STARTED since the entry-time warm: a
  /// session runs up to twelve hours on one warm, so without this a class that
  /// finished at 7am still sits under a Book pill at 8pm labelled "Today".
  void _pruneShowcaseClasses() {
    if (_showcaseClassesCache.isEmpty) return;
    final now = _now();
    _showcaseClassesCache = _showcaseClassesCache
        .where((i) => i.occurredAt.isAfter(now))
        .toList();
  }

  /// Start the glance's hold — but only once the reveal's LAST beat has landed
  /// ([kKioskGlanceLastBeat]). The full countdown value is emitted immediately;
  /// what waits is the DECREMENT, so the reveal never eats reading time. Both
  /// phases share [_glanceTimer], so every cancel site kills the auto-return
  /// whichever phase it is in.
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
  /// restarts the hold on an already-revealed glance, which must not wait out
  /// the last beat again.
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

  /// Give the glance its WHOLE hold back after the modal closes over it — the
  /// member spent their read-time in the modal, so handing back the seconds
  /// that were left would eject them mid-sentence. It drains immediately: the
  /// glance behind the modal is settled, no reveal left to wait for.
  void _restartGlanceHold() {
    emit(state.copyWith(glanceCountdown: kKioskGlanceHold.inSeconds));
    _startGlanceCountdown();
  }

  // ── "Get the app" modal (UX-5) ──

  /// Open the "Get the app" modal — from a tap on the glance (a founder ruling:
  /// the glance tap offers the app rather than ejecting home) or the home adopt
  /// strip. It pauses the glance's auto-return in EITHER phase plus any idle
  /// guard, and starts the modal's own clock. A pure informational overlay: it
  /// does NOT begin a member flow (no [KioskSessionCubit.beginFlow]), so it
  /// never touches the grace-window bookkeeping. Idempotent while open.
  void openAppModal() {
    if (state.appModalOpen) return;
    // The modal's own 60s clock is the sole timer while it is up.
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

  /// The modal's 60-second auto-close, which goes HOME unlike Done: a minute of
  /// no interaction means nobody is standing at the kiosk, and dropping back
  /// onto a glance would leave a member's name, streak and points on a shared
  /// iPad for the next person to read.
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

  /// Close the modal (Done) and return to WHATEVER WAS UNDERNEATH IT — calling
  /// [goHome] here instead ejects a member out of their own check-in result.
  /// Returning to the glance restarts its hold at full (the reveal does not
  /// replay — the screen stayed mounted behind the overlay); returning home
  /// re-arms the idle guard. Idempotent when closed, and it always cancels the
  /// modal's timer so no late tick can fire a [goHome].
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

  /// Abandon any in-progress draft and return to the idle home.
  ///
  /// This is the ONE abandon path — the glance's Done, the idle timeout, the
  /// app modal's EXPIRY (never its Done) and the class-pick escape all come
  /// through here. Never hand-roll another: dropping [_endFlowIfStarted] leaks
  /// the session's in-progress flow count and the kiosk then never signs itself
  /// out at lockout, and dropping the sequence bumps lets a late fetch paint
  /// the previous member's data over the next person's home.
  void goHome() {
    _searchDebounce?.cancel();
    _glanceTimer?.cancel();
    _appModalTimer?.cancel();
    _searchSeq++;
    _classesSeq++;
    _glanceSeq++; // drop any in-flight glance fetch
    _endFlowIfStarted();
    _pruneShowcaseClasses();
    emit(_freshHome);
    _syncIdleTimer();
  }

  // ── Flow-idle guard ──

  /// Any member interaction: dismiss the idle warning and reset the clock.
  /// Wired to a pointer listener over the whole flow surface.
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
    // The glance and the modal each run their own clock.
    if (state.view == KioskView.checkedIn) return;
    if (state.appModalOpen) return;
    // The signup lane runs its OWN guard inside `KioskSignupCubit` — only that
    // cubit knows which of its steps may be interrupted. A second guard would
    // race it, abandoning to home mid-signup without releasing its flow count.
    if (state.view == KioskView.signup) return;
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
