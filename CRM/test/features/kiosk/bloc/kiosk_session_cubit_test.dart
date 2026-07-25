import 'dart:async';

import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_state.dart';
import 'package:crm/features/kiosk/data/kiosk_server_clock.dart';
import 'package:crm/features/kiosk/data/kiosk_session_store.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockKioskSessionStore extends Mock implements KioskSessionStore {}

class _MockKioskServerClock extends Mock implements KioskServerClock {}

/// The kiosk session cubit — the security state machine. The runway is
/// absolute (member interaction never extends it), exit is sign-out-first /
/// clear-only-after-confirmed, and every ambiguous branch fails closed to the
/// locked screen, never to the admin workspace. SEC-1/2/3 in the group names
/// are the three hardening properties: no admin-flash on restore, a durable
/// flag before entering, and a SERVER-anchored deadline a rolled-back device
/// clock cannot extend. A fixed clock + `fakeAsync` drive the timers; the
/// mocked [KioskServerClock] agrees with the device clock at [t0] unless a
/// SEC-3 test overrides it.
void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);
  const runway = Duration(hours: 12);
  const grace = Duration(minutes: 15);
  final deadline = t0.add(runway);

  late _MockKioskSessionStore store;
  late _MockKioskServerClock serverClock;
  late int signOutCalls;
  late bool sessionPresent;

  setUpAll(() {
    registerFallbackValue(DateTime.utc(2020));
  });

  setUp(() {
    store = _MockKioskSessionStore();
    serverClock = _MockKioskServerClock();
    signOutCalls = 0;
    sessionPresent = true; // a live admin session exists while in kiosk
    when(() => store.read()).thenAnswer((_) async => (false, null));
    when(() => store.save(any())).thenAnswer((_) async {});
    when(() => store.clear()).thenAnswer((_) async {});
    when(() => serverClock.serverNow()).thenAnswer((_) async => t0);
  });

  KioskSessionCubit build({DateTime Function()? now}) => KioskSessionCubit(
        store: store,
        serverClock: serverClock,
        dispatchSignOut: () => signOutCalls++,
        sessionGone: () => !sessionPresent,
        now: now ?? () => t0,
        runway: runway,
        graceWindow: grace,
      );

  group('initial state / restore (SEC-1: no boot/reload admin-flash)', () {
    test('starts synchronously in restoring, before _restore resolves', () {
      // No await: the constructor must seed [restoring] BEFORE the async read,
      // so the very first gate build sees the loader, never the workspace.
      final cubit = build();
      expect(cubit.state.status, KioskStatus.restoring);
      expect(cubit.state.isRestoring, isTrue);
      expect(cubit.state.isKioskVisible, isFalse);
      expect(cubit.state.isEnded, isFalse);
      cubit.close();
    });

    test('nothing persisted → resolves restoring to inactive (workspace)',
        () async {
      final cubit = build();
      await pumpEventQueue();
      expect(cubit.state.status, KioskStatus.inactive);
      expect(signOutCalls, 0);
      await cubit.close();
    });

    test(
        'a live flag restores restoring → active WITHOUT ever passing through '
        'inactive (never mounts the workspace mid-read)', () async {
      final future = t0.add(const Duration(hours: 6));
      when(() => store.read()).thenAnswer((_) async => (true, future));
      final cubit = build();
      final seen = <KioskStatus>[];
      final sub = cubit.stream.listen((s) => seen.add(s.status));
      await pumpEventQueue();
      expect(cubit.state.status, KioskStatus.active);
      expect(cubit.state.deadline, future);
      // inactive is the ONLY status that mounts _MembersWorkspace — it must
      // never appear on the restore path for a live kiosk flag.
      expect(seen, isNot(contains(KioskStatus.inactive)));
      expect(seen, [KioskStatus.active]);
      expect(signOutCalls, 0);
      await sub.cancel();
      await cubit.close();
    });

    test('persisted + now inside the grace window → restores locked',
        () async {
      // Deadline 10 min out → past the lockout mark (deadline − 15 min).
      final near = t0.add(const Duration(minutes: 10));
      when(() => store.read()).thenAnswer((_) async => (true, near));
      final cubit = build();
      await pumpEventQueue();
      expect(cubit.state.status, KioskStatus.locked);
      expect(signOutCalls, 0);
      await cubit.close();
    });

    test('persisted + now >= deadline → ended + sign out (never active)',
        () async {
      final past = t0.subtract(const Duration(minutes: 1));
      when(() => store.read()).thenAnswer((_) async => (true, past));
      final cubit = build();
      await pumpEventQueue();
      expect(cubit.state.status, KioskStatus.ended);
      expect(cubit.state.isKioskVisible, isFalse);
      expect(signOutCalls, 1);
      await cubit.close();
    });
  });

  group('enter (SEC-2: durable before entering)', () {
    test('enterKiosk persists the flag+deadline, then emits active', () async {
      final cubit = build();
      await pumpEventQueue(); // restore settles → inactive
      await cubit.enterKiosk();
      expect(
        cubit.state,
        KioskSessionState(status: KioskStatus.active, deadline: deadline),
      );
      verify(() => store.save(deadline)).called(1);
      await cubit.close();
    });

    test('does NOT reach active until the save future completes', () async {
      final cubit = build();
      await pumpEventQueue(); // inactive
      final saveGate = Completer<void>();
      when(() => store.save(any())).thenAnswer((_) => saveGate.future);

      final entering = cubit.enterKiosk();
      await pumpEventQueue();
      // Save in flight → the flag isn't durable, so we must NOT have entered.
      // This is the window a reload could otherwise catch.
      expect(cubit.state.status, KioskStatus.inactive);

      saveGate.complete();
      await entering;
      expect(cubit.state.status, KioskStatus.active);
      await cubit.close();
    });

    test('a FAILED save does not enter (stays inactive, fail-closed)',
        () async {
      final cubit = build();
      await pumpEventQueue(); // inactive
      when(() => store.save(any()))
          .thenAnswer((_) async => throw Exception('localStorage full'));

      await cubit.enterKiosk();
      expect(cubit.state.status, KioskStatus.inactive);
      expect(cubit.state.isKioskVisible, isFalse);
      await cubit.close();
    });
  });

  group('exit', () {
    test(
        'exitKiosk dispatches sign-out first but does NOT clear persistence or '
        'change state — the clear waits for a confirmed sign-out', () async {
      final cubit = build();
      await pumpEventQueue(); // inactive
      await cubit.enterKiosk(); // active
      cubit.exitKiosk();
      expect(cubit.state.status, KioskStatus.active);
      expect(signOutCalls, 1);
      verifyNever(() => store.clear());
      await cubit.close();
    });
  });

  group('sign-out confirmation (fate-share clear)', () {
    test(
        'handleSignedOut clears persistence + goes inactive once the session '
        'is actually gone', () async {
      final cubit = build();
      await pumpEventQueue();
      await cubit.enterKiosk();
      sessionPresent = false; // sign-out completed, session cleared
      await cubit.handleSignedOut();
      expect(cubit.state, const KioskSessionState.inactive());
      verify(() => store.clear()).called(1);
      await cubit.close();
    });

    test(
        'a FAILED/absent sign-out (session still present) leaves kiosk active '
        'and keeps persistence (fail-closed)', () async {
      final cubit = build();
      await pumpEventQueue();
      await cubit.enterKiosk();
      sessionPresent = true; // the sign-out did not clear the session
      await cubit.handleSignedOut();
      expect(cubit.state.status, KioskStatus.active);
      verifyNever(() => store.clear());
      await cubit.close();
    });
  });

  group('runway timers', () {
    test('idle at lockout (T+11h45) signs out 15 minutes early', () {
      fakeAsync((async) {
        final cubit = build();
        async.flushMicrotasks(); // restore settles → inactive
        cubit.enterKiosk();
        async.flushMicrotasks(); // save completes → timers scheduled, active
        expect(cubit.state.status, KioskStatus.active);

        async.elapse(runway - grace); // T+11h45, nothing mid-flow
        expect(cubit.state.status, KioskStatus.ended);
        expect(signOutCalls, 1);

        async.elapse(grace); // T+12h — the hard revoke must not double-fire
        expect(signOutCalls, 1);
        cubit.close();
      });
    });

    test(
        'a flow in progress rides through lockout; the hard revoke (T+12h) '
        'signs out regardless', () {
      fakeAsync((async) {
        final cubit = build();
        async.flushMicrotasks();
        cubit.enterKiosk();
        async.flushMicrotasks();
        cubit.beginFlow(); // a signup is mid-flight

        async.elapse(runway - grace); // T+11h45
        expect(cubit.state.status, KioskStatus.locked);
        expect(cubit.state.canStartFlow, isFalse); // no new flows may start
        expect(signOutCalls, 0);

        async.elapse(grace); // T+12h
        expect(cubit.state.status, KioskStatus.ended);
        expect(signOutCalls, 1);
        cubit.close();
      });
    });
  });

  group('SEC-3: server-anchored runway', () {
    test('enterKiosk pins the deadline off SERVER now, not the device clock',
        () async {
      // Device clock reads t0; the server is one hour ahead.
      final serverAhead = t0.add(const Duration(hours: 1));
      when(() => serverClock.serverNow())
          .thenAnswer((_) async => serverAhead);
      final cubit = build(now: () => t0);
      await pumpEventQueue(); // restore settles → inactive
      await cubit.enterKiosk();
      final expected = serverAhead.add(runway); // NOT t0 + runway
      expect(cubit.state.deadline, expected);
      verify(() => store.save(expected)).called(1);
      await cubit.close();
    });

    test('enterKiosk falls back to the device clock when the server is down',
        () async {
      when(() => serverClock.serverNow()).thenAnswer((_) async => null);
      final cubit = build(now: () => t0);
      await pumpEventQueue();
      await cubit.enterKiosk();
      expect(cubit.state.deadline, deadline); // t0 + runway
      await cubit.close();
    });

    test(
        'restore ends the session when the SERVER clock is past the deadline '
        'even though a rolled-back device clock reads "before"', () async {
      // Persisted deadline t0+12h; the device clock is rolled back to t0 and
      // reads "before" it, but the server reads an hour past. Server wins.
      when(() => store.read()).thenAnswer((_) async => (true, deadline));
      when(() => serverClock.serverNow())
          .thenAnswer((_) async => deadline.add(const Duration(hours: 1)));
      final cubit = build(now: () => t0);
      await pumpEventQueue();
      expect(cubit.state.status, KioskStatus.ended);
      expect(cubit.state.isKioskVisible, isFalse);
      expect(signOutCalls, 1);
      await cubit.close();
    });

    test(
        'restore fails CLOSED when the server is unavailable AND the device '
        'clock is near the deadline (would otherwise restore locked)',
        () async {
      // Deadline 10 min out → past the lockout mark (deadline − 15 min), so
      // the device clock alone would restore [locked]. That close to expiry an
      // unreachable server is not trusted away: end + sign out.
      final near = t0.add(const Duration(minutes: 10));
      when(() => store.read()).thenAnswer((_) async => (true, near));
      when(() => serverClock.serverNow()).thenAnswer((_) async => null);
      final cubit = build(now: () => t0);
      await pumpEventQueue();
      expect(cubit.state.status, KioskStatus.ended);
      expect(signOutCalls, 1);
      await cubit.close();
    });

    test(
        'restore trusts a comfortably-early device clock when the server is '
        'unavailable (offline kiosk still resumes)', () async {
      // Deadline 6h out → nowhere near the lockout mark, so an offline reload
      // resumes rather than failing closed on every network blip.
      final future = t0.add(const Duration(hours: 6));
      when(() => store.read()).thenAnswer((_) async => (true, future));
      when(() => serverClock.serverNow()).thenAnswer((_) async => null);
      final cubit = build(now: () => t0);
      await pumpEventQueue();
      expect(cubit.state.status, KioskStatus.active);
      expect(cubit.state.deadline, future);
      expect(signOutCalls, 0);
      await cubit.close();
    });
  });
}
