import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/kiosk/bloc/kiosk_session_state.dart';
import 'package:crm/features/kiosk/data/kiosk_server_clock.dart';
import 'package:crm/features/kiosk/data/kiosk_session_store.dart';

/// The security state machine behind CRM Kiosk Mode. Provided **above the auth
/// gate** (see `main.dart`), so entering kiosk swaps the whole authenticated
/// subtree for the member surface without signing the admin out — while
/// *leaving* kiosk always signs out.
///
/// A [Cubit] (not the `ChangeNotifier` the original sketch used) so it matches
/// the codebase's Bloc idiom and gets `bloc_test` coverage.
///
/// ## The runway
/// Entry pins an absolute [KioskSessionState.deadline] = `now + runway`
/// (default 12h). Member interaction never extends it — a stolen or forgotten
/// iPad always loses access within the runway. Two timers ride it:
///
/// ### Server-anchored (SEC-3)
/// `now` here is the SERVER clock, not the device clock. Both the entry pin
/// and the reload expiry check read the server time via [KioskServerClock]
/// (the HTTP `Date` header), so a supervised iPad whose clock is rolled *back*
/// can't read "still before the deadline" and extend the member surface past
/// its true T+12h. The exposure only ever existed across a reload — a live
/// session's timers are duration-based (monotonic). When the server clock is
/// unreachable, entry falls back to the device clock (staff is physically
/// present), and restore **fails closed** near the deadline (below) rather
/// than trusting a possibly-rolled-back device clock.
///
/// - **lockout** at `deadline − graceWindow` (T+11h45): block *new* flow
///   starts. If nothing is mid-flow → sign out now (idle, 15 min early). If a
///   flow is in progress → let it ride ([locked]).
/// - **hard revoke** at `deadline` (T+12h): sign out unconditionally.
///
/// ## Fail-closed
/// The persisted flag fate-shares the browser localStorage with the Supabase
/// session, and the flag is only honored inside the authenticated subtree, so a
/// flag without a session is inert. On top of that: [exitKiosk] signs out
/// *first* and persistence is cleared **only** once the session is confirmed
/// gone ([handleSignedOut] gated on [_sessionGone]) — a failed sign-out leaves
/// the kiosk up rather than dropping to admin.
///
/// ## Boot: no admin-flash
/// The cubit starts synchronously in [KioskStatus.restoring] (before the async
/// [_restore] reads localStorage), which the gate renders as a neutral loader —
/// never the admin workspace. So on a reload/refresh the persisted flag is read
/// *before* anything decides whether to mount the admin workspace; a member on
/// a kiosk iPad can't point the address bar at an admin route and have it render
/// during the restore window. `_restore` resolves [restoring] to [inactive]
/// when nothing is persisted, so a genuine non-kiosk admin still reaches the
/// workspace once the read completes.
class KioskSessionCubit extends Cubit<KioskSessionState> {
  KioskSessionCubit({
    required KioskSessionStore store,
    required void Function() dispatchSignOut,
    required bool Function() sessionGone,
    KioskServerClock? serverClock,
    DateTime Function() now = DateTime.now,
    Duration runway = const Duration(hours: 12),
    Duration graceWindow = const Duration(minutes: 15),
  })  : _store = store,
        _dispatchSignOut = dispatchSignOut,
        _sessionGone = sessionGone,
        _serverClock = serverClock ?? KioskServerClock(),
        _now = now,
        _runway = runway,
        _graceWindow = graceWindow,
        super(const KioskSessionState.restoring()) {
    unawaited(_restore());
  }

  final KioskSessionStore _store;

  /// Reads the SERVER clock (HTTP `Date`) so the runway can't be extended by a
  /// rolled-back device clock. Returns null when unavailable; the entry/restore
  /// paths fall back to [_now] (the device clock) — restore fails closed near
  /// the deadline in that case.
  final KioskServerClock _serverClock;

  /// Starts a sign-out (dispatches `LoginSignOutRequested`). Kept as a plain
  /// callback so the cubit never imports the login feature.
  final void Function() _dispatchSignOut;

  /// True once the Supabase session is actually gone. Gates the fail-closed
  /// persistence clear so a failed sign-out never wipes the flag.
  final bool Function() _sessionGone;

  /// The DEVICE clock — the fallback used only when [_serverClock] is
  /// unreachable (and, at restore, gated by the near-deadline fail-closed
  /// rule). The server clock is the source of truth for the runway.
  final DateTime Function() _now;
  final Duration _runway;
  final Duration _graceWindow;

  /// Cancel-safe timer list, modeled on `InvoicePoller`: cancel-before-restart
  /// and cancel on close, so only one runway's worth of timers is ever live.
  final List<Timer> _timers = [];

  /// How many check-in / signup flows are mid-progress. Drives the lockout
  /// decision (idle → sign out now; busy → grace). In-memory only: a reload
  /// resets it to 0, which is correct — a reload kills any in-flight flow.
  int _flowCount = 0;

  // ── Entry / exit ──

  /// Enter kiosk: persist the flag + absolute deadline **first**, then start the
  /// runway timers and flip to [KioskStatus.active].
  ///
  /// The deadline is anchored to the SERVER clock (SEC-3) so a rolled-back
  /// device clock can never mint a longer-than-runway session. The server read
  /// falls back to the device clock only when the backend is unreachable at
  /// entry — staff is physically present, so an untampered device clock is an
  /// acceptable baseline.
  ///
  /// The save is *awaited before* the state flips (the caller awaits this): a
  /// reload in the microtask gap must never catch a live [active] session whose
  /// flag has not been written yet — that would restore straight into the admin
  /// workspace (fail-OPEN). Persist-then-enter closes that window. A failed save
  /// does **not** enter: the state is left untouched (the admin keeps the
  /// workspace) rather than entering a kiosk the next boot can't restore.
  Future<void> enterKiosk() async {
    final base = await _serverClock.serverNow() ?? _now();
    if (isClosed) return;
    final deadline = base.add(_runway);
    try {
      await _store.save(deadline);
    } catch (e, s) {
      log('Kiosk enter aborted: flag persist failed',
          error: e, stackTrace: s);
      return; // fail-closed: never enter without a durable flag
    }
    if (isClosed) return;
    _flowCount = 0;
    _scheduleTimers(deadline, base);
    emit(KioskSessionState(status: KioskStatus.active, deadline: deadline));
  }

  /// Leave kiosk: sign out **first**. Persistence is *not* touched here — it is
  /// cleared only once [handleSignedOut] confirms the session is gone. If the
  /// sign-out fails the iPad stays on the kiosk screen (fail-closed), never the
  /// admin workspace.
  void exitKiosk() => _dispatchSignOut();

  // ── Flow tracking (Phase C/D check-in / signup call these) ──

  /// Mark a member flow (check-in / signup) as started, so a lockout that lands
  /// mid-flow grants the grace window instead of signing out immediately.
  void beginFlow() => _flowCount++;

  /// Mark a member flow as finished. Clamped at zero.
  void endFlow() {
    if (_flowCount > 0) _flowCount--;
  }

  // ── Sign-out confirmation (the fate-share clear point) ──

  /// Called when the login bloc reports the session is gone
  /// (`LoginUnauthenticated`). Clears persistence and resets to
  /// [KioskStatus.inactive] — but **only** if the session is genuinely gone.
  /// A failed sign-out that left the session intact must keep the flag, so the
  /// next boot restores the kiosk rather than exposing admin.
  Future<void> handleSignedOut() async {
    if (!_sessionGone()) return; // fail-closed: keep the flag, stay in kiosk
    _cancelTimers();
    _flowCount = 0;
    await _store.clear();
    if (isClosed) return;
    emit(const KioskSessionState.inactive());
  }

  // ── Timers ──

  /// Schedule the lockout + hard-revoke timers off [now] — the same reference
  /// instant the deadline was judged against (server time when available). The
  /// timers themselves are duration-based (monotonic), so passing the
  /// server-derived remaining time keeps a rolled-back device clock from
  /// stretching them after a restore.
  void _scheduleTimers(DateTime deadline, DateTime now) {
    _cancelTimers();
    final untilLockout = deadline.subtract(_graceWindow).difference(now);
    final untilRevoke = deadline.difference(now);
    // A non-positive offset means that moment already passed (e.g. restoring
    // into the grace window) — skip that timer; the state emitted below already
    // reflects it.
    if (untilLockout > Duration.zero) {
      _timers.add(Timer(untilLockout, _onLockout));
    }
    if (untilRevoke > Duration.zero) {
      _timers.add(Timer(untilRevoke, _onHardRevoke));
    }
  }

  void _onLockout() {
    if (_flowCount == 0) {
      // Idle at T+11h45 → sign out 15 minutes early.
      _endSession();
      return;
    }
    // A flow is mid-signup: block new starts, let this one ride to the hard
    // revoke.
    emit(KioskSessionState(
      status: KioskStatus.locked,
      deadline: state.deadline,
    ));
  }

  void _onHardRevoke() => _endSession();

  /// Terminate the runway: show the fail-closed [KioskStatus.ended] screen and
  /// drive a sign-out. Persistence is cleared later by [handleSignedOut] once
  /// the session is confirmed gone.
  void _endSession() {
    _cancelTimers();
    emit(KioskSessionState(
      status: KioskStatus.ended,
      deadline: state.deadline,
    ));
    _dispatchSignOut();
  }

  void _cancelTimers() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  // ── Restore (boot) ──

  Future<void> _restore() async {
    final (active, deadline) = await _store.read();
    if (isClosed) return;
    if (!active || deadline == null) {
      // Nothing persisted — a genuine non-kiosk admin. Resolve the initial
      // [restoring] loader to [inactive] so the gate mounts the workspace.
      emit(const KioskSessionState.inactive());
      return;
    }
    // Judge expiry against the SERVER clock (SEC-3): a rolled-back device clock
    // reads "before the deadline" forever, so it can't be trusted to bound the
    // runway across a reload. Only reached once a kiosk flag is persisted, so a
    // normal admin boot never pays for this network read.
    final serverNow = await _serverClock.serverNow();
    if (isClosed) return;
    final deviceNow = _now();
    final effectiveNow = serverNow ?? deviceNow;

    // Fail CLOSED when the server clock is unavailable AND the device clock
    // already places us at/past the lockout mark: a possibly-rolled-back device
    // clock is not trustworthy that close to expiry, so end rather than risk
    // extending the surface. A comfortably-early offline reload still trusts the
    // device clock below — otherwise an offline kiosk could never resume.
    final deviceNearDeadline =
        !deviceNow.isBefore(deadline.subtract(_graceWindow));
    if (serverNow == null && deviceNearDeadline) {
      emit(KioskSessionState(status: KioskStatus.ended, deadline: deadline));
      _dispatchSignOut();
      return;
    }

    if (!effectiveNow.isBefore(deadline)) {
      // The runway blew while the tab was closed. Fail closed: don't enter
      // kiosk — drive a sign-out and show the ended (locked) screen.
      emit(KioskSessionState(status: KioskStatus.ended, deadline: deadline));
      _dispatchSignOut();
      return;
    }
    _scheduleTimers(deadline, effectiveNow);
    // Reopened inside the grace window (past lockout, before the deadline):
    // restore straight to [locked]. The idle-sign-out is a property of the
    // lockout *transition* on a live session, not of restore — the hard-revoke
    // timer (still scheduled above) bounds it at the deadline.
    final locked = !effectiveNow.isBefore(deadline.subtract(_graceWindow));
    emit(KioskSessionState(
      status: locked ? KioskStatus.locked : KioskStatus.active,
      deadline: deadline,
    ));
  }

  @override
  Future<void> close() {
    _cancelTimers();
    return super.close();
  }
}
