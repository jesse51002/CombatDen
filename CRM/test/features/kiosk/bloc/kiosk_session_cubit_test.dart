import 'dart:async';

import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_state.dart';
import 'package:crm/features/kiosk/data/kiosk_session_store.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockKioskSessionStore extends Mock implements KioskSessionStore {}

/// The kiosk cubit is the Phase B security state machine. The runway is
/// absolute (never extended by member interaction), the exit order is
/// sign-out-first / clear-only-after-confirmed, and every ambiguous branch
/// fails closed to the locked screen — never to the admin workspace. A fixed
/// injected clock makes the deadline deterministic; `fakeAsync` drives the
/// 11h45 / 12h timers in virtual time.
///
/// Two hardening properties are exercised here:
/// - **SEC-1 (no admin-flash):** the cubit starts synchronously in
///   [KioskStatus.restoring] (which the gate renders as a loader, never the
///   admin workspace) and resolves it only once the persisted flag has been
///   read — a boot/reload never observes a workspace-mounting state mid-read.
/// - **SEC-2 (durable before entering):** `enterKiosk` awaits the flag persist
///   BEFORE flipping to [active], so a reload in the microtask gap can't strand
///   a live session without its flag; a failed save does not enter at all.
void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);
  const runway = Duration(hours: 12);
  const grace = Duration(minutes: 15);
  final deadline = t0.add(runway);

  late _MockKioskSessionStore store;
  late int signOutCalls;
  late bool sessionPresent;

  setUpAll(() {
    registerFallbackValue(DateTime.utc(2020));
  });

  setUp(() {
    store = _MockKioskSessionStore();
    signOutCalls = 0;
    sessionPresent = true; // a live admin session exists while in kiosk
    when(() => store.read()).thenAnswer((_) async => (false, null));
    when(() => store.save(any())).thenAnswer((_) async {});
    when(() => store.clear()).thenAnswer((_) async {});
  });

  KioskSessionCubit build({DateTime Function()? now}) => KioskSessionCubit(
        store: store,
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
      // Save still in flight → the flag isn't durable yet, so we must NOT have
      // entered kiosk. This is the window a reload could otherwise catch.
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
}
