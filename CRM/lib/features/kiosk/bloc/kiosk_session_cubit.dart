import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/kiosk/bloc/kiosk_session_state.dart';
import 'package:crm/features/kiosk/data/kiosk_server_clock.dart';
import 'package:crm/features/kiosk/data/kiosk_session_store.dart';

/// The security state machine behind CRM Kiosk Mode. Provided above the auth
/// gate (see `main.dart`), so entering kiosk swaps the whole authenticated
/// subtree for the member surface without signing the admin out — while
/// *leaving* kiosk always signs out.
///
/// Entry pins an absolute [KioskSessionState.deadline] = `now + runway` (12h)
/// off the SERVER clock, never the device clock ([KioskServerClock] carries the
/// why). Member interaction never extends it — a stolen or forgotten iPad
/// always loses access within the runway. Two timers ride it: lockout at
/// `deadline − graceWindow` blocks NEW flow starts (idle → sign out early; a
/// flow mid-progress rides on, [KioskStatus.locked]), and hard revoke at
/// `deadline` signs out unconditionally.
///
/// Everything here fails CLOSED: the flag is persisted before entry, cleared
/// only once the sign-out is confirmed, and a restore that cannot trust the
/// clock ends the session. It starts synchronously in [KioskStatus.restoring]
/// so a boot can never flash an admin route.
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

  /// Null when unavailable: entry falls back to [_now], restore fails closed
  /// near the deadline.
  final KioskServerClock _serverClock;

  /// Starts a sign-out. A plain callback so the cubit never imports login.
  final void Function() _dispatchSignOut;

  /// True once the Supabase session is actually gone. Gates the fail-closed
  /// persistence clear so a failed sign-out never wipes the flag.
  final bool Function() _sessionGone;

  /// The DEVICE clock — a fallback only, used when [_serverClock] is
  /// unreachable (and at restore, gated by the near-deadline fail-closed rule).
  final DateTime Function() _now;
  final Duration _runway;
  final Duration _graceWindow;

  /// Cancel-before-restart and cancel on close, so only one runway's worth of
  /// timers is ever live.
  final List<Timer> _timers = [];

  /// How many check-in / signup flows are mid-progress; drives the lockout
  /// decision. In-memory only: a reload resets it to 0, which is correct
  /// because a reload kills any in-flight flow.
  int _flowCount = 0;

  // ── Entry / exit ──

  /// Enter kiosk: persist the flag + absolute deadline FIRST, then start the
  /// runway timers and flip to [KioskStatus.active]. The save is awaited before
  /// the state flips — a reload in the microtask gap must never catch a live
  /// active session whose flag is not yet written, which would restore straight
  /// into the admin workspace — and a failed save does not enter at all. The
  /// deadline falls back to the device clock only when the backend is
  /// unreachable at entry, where staff is physically present.
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

  /// Leave kiosk: sign out FIRST. Persistence is cleared only once
  /// [handleSignedOut] confirms the session is gone, so a failed sign-out
  /// leaves the iPad on the kiosk screen rather than the admin workspace.
  void exitKiosk() => _dispatchSignOut();

  // ── Flow tracking (the check-in / signup lanes call these) ──

  /// Mark a member flow (check-in / signup) as started, so a lockout that lands
  /// mid-flow grants the grace window instead of signing out immediately.
  void beginFlow() => _flowCount++;

  /// Mark a member flow as finished. Clamped at zero.
  void endFlow() {
    if (_flowCount > 0) _flowCount--;
  }

  // ── Sign-out confirmation (the fate-share clear point) ──

  /// Called when the login bloc reports the session is gone. Clears persistence
  /// and resets to [KioskStatus.inactive] — but ONLY if the session really is
  /// gone: a failed sign-out must keep the flag so the next boot restores the
  /// kiosk rather than exposing admin.
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
  /// instant the deadline was judged against. They are duration-based
  /// (monotonic), so a rolled-back device clock can't stretch them.
  void _scheduleTimers(DateTime deadline, DateTime now) {
    _cancelTimers();
    final untilLockout = deadline.subtract(_graceWindow).difference(now);
    final untilRevoke = deadline.difference(now);
    // A non-positive offset means that moment already passed (restoring into
    // the grace window) — skip it; the emitted state reflects it.
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
    // Mid-flow: block new starts, let this one ride to the hard revoke.
    emit(KioskSessionState(
      status: KioskStatus.locked,
      deadline: state.deadline,
    ));
  }

  void _onHardRevoke() => _endSession();

  /// Terminate the runway: show the fail-closed [KioskStatus.ended] screen and
  /// drive a sign-out; [handleSignedOut] clears persistence afterwards.
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
      // Nothing persisted — a genuine non-kiosk admin; resolve the restoring
      // loader so the gate mounts the workspace.
      emit(const KioskSessionState.inactive());
      return;
    }
    // Judge expiry against the SERVER clock: a rolled-back device clock reads
    // "before the deadline" forever. Only reached with a kiosk flag persisted,
    // so a normal admin boot never pays for this network read.
    final serverNow = await _serverClock.serverNow();
    if (isClosed) return;
    final deviceNow = _now();
    final effectiveNow = serverNow ?? deviceNow;

    // Fail CLOSED when the server clock is unavailable AND the device clock
    // already places us at/past the lockout mark: that close to expiry a
    // possibly-rolled-back device clock is not trustworthy. A comfortably-early
    // offline reload still trusts it, or an offline kiosk could never resume.
    final deviceNearDeadline =
        !deviceNow.isBefore(deadline.subtract(_graceWindow));
    if (serverNow == null && deviceNearDeadline) {
      emit(KioskSessionState(status: KioskStatus.ended, deadline: deadline));
      _dispatchSignOut();
      return;
    }

    if (!effectiveNow.isBefore(deadline)) {
      // The runway blew while the tab was closed — fail closed.
      emit(KioskSessionState(status: KioskStatus.ended, deadline: deadline));
      _dispatchSignOut();
      return;
    }
    _scheduleTimers(deadline, effectiveNow);
    // Reopened inside the grace window: restore straight to locked. The idle
    // sign-out belongs to the lockout transition on a live session, not to
    // restore; the hard-revoke timer above still bounds it at the deadline.
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
