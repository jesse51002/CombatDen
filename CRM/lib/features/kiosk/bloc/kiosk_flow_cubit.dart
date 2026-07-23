import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:crm/features/check_in/data/models/check_in_request.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
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
/// runs on the idle home screen (home is the rest state). Distinct from the
/// Phase B 12h runway and any Phase C2 glance auto-return.
const Duration kKioskIdleTimeout = Duration(minutes: 5);

/// The visible countdown on the idle warning before it abandons the draft and
/// returns to home. (Jesse to confirm 30 vs 60 — this one line is the switch.)
const Duration kKioskIdleCountdown = Duration(seconds: 30);

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
    required KioskSessionCubit session,
    required String gymId,
    DateTime Function() now = DateTime.now,
  })  : _membersRepo = membersRepository,
        _scheduleRepo = scheduleRepository,
        _memberRepo = memberRepository,
        _session = session,
        _gymId = gymId,
        _now = now,
        super(const KioskFlowState.home());

  final MembersListRepository _membersRepo;
  final ScheduleRepository _scheduleRepo;
  final MemberRepository _memberRepo;
  final KioskSessionCubit _session;
  final String _gymId;
  final DateTime Function() _now;

  /// Backend `occurrence_date` is a bare gym-local `YYYY-MM-DD` (mirrors
  /// `ScheduleRepository`).
  static final DateFormat _dateParam = DateFormat('yyyy-MM-dd');

  Timer? _searchDebounce;
  Timer? _idleTimer;
  Timer? _countdownTimer;
  int _searchSeq = 0;
  int _classesSeq = 0;

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
      final open = all
          .where((i) =>
              !i.isCancelled && occurrenceCheckInOpen(i.occurredAt, now))
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
  /// to the blame-free blocked screen. Either terminal ends the flow.
  Future<void> selectClass(EffectiveClassInstance occ) async {
    registerActivity();
    final member = state.selectedMember;
    if (member == null || state.view == KioskView.checkingIn) return;
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
      if (isClosed) return;
      _endFlowIfStarted();
      if (resp.logId == null) {
        emit(state.copyWith(
          view: KioskView.blocked,
          blockedReason: resp.skipReason,
        ));
      } else {
        emit(state.copyWith(view: KioskView.checkedIn, checkInResult: resp));
      }
      _syncIdleTimer();
    } catch (e, st) {
      log('Kiosk check-in failed', error: e, stackTrace: st);
      if (isClosed) return;
      _endFlowIfStarted();
      emit(state.copyWith(view: KioskView.blocked, checkInFailed: true));
      _syncIdleTimer();
    }
  }

  // ── Return to home (Done / cancel / idle timeout) ──

  /// Abandon any in-progress draft and return to the idle home screen. Ends
  /// the flow if one was started; cancels the search + idle timers.
  void goHome() {
    _searchDebounce?.cancel();
    _searchSeq++;
    _classesSeq++;
    _endFlowIfStarted();
    emit(const KioskFlowState.home());
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
    return super.close();
  }
}
