import 'package:bloc_test/bloc_test.dart';
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

  group('enter / exit', () {
    blocTest<KioskSessionCubit, KioskSessionState>(
      'enterKiosk emits active with the +12h deadline and persists it',
      build: build,
      act: (cubit) => cubit.enterKiosk(),
      expect: () => [
        KioskSessionState(status: KioskStatus.active, deadline: deadline),
      ],
      verify: (_) => verify(() => store.save(deadline)).called(1),
    );

    blocTest<KioskSessionCubit, KioskSessionState>(
      'exitKiosk dispatches sign-out first but does NOT clear persistence or '
      'change state — the clear waits for a confirmed sign-out',
      build: build,
      act: (cubit) {
        cubit.enterKiosk();
        cubit.exitKiosk();
      },
      expect: () => [
        KioskSessionState(status: KioskStatus.active, deadline: deadline),
      ],
      verify: (_) {
        expect(signOutCalls, 1);
        verifyNever(() => store.clear());
      },
    );
  });

  group('sign-out confirmation (fate-share clear)', () {
    blocTest<KioskSessionCubit, KioskSessionState>(
      'handleSignedOut clears persistence + goes inactive once the session '
      'is actually gone',
      build: build,
      act: (cubit) async {
        cubit.enterKiosk();
        sessionPresent = false; // sign-out completed, session cleared
        await cubit.handleSignedOut();
      },
      expect: () => [
        KioskSessionState(status: KioskStatus.active, deadline: deadline),
        const KioskSessionState.inactive(),
      ],
      verify: (_) => verify(() => store.clear()).called(1),
    );

    blocTest<KioskSessionCubit, KioskSessionState>(
      'a FAILED/absent sign-out (session still present) leaves kiosk active '
      'and keeps persistence (fail-closed)',
      build: build,
      act: (cubit) async {
        cubit.enterKiosk();
        sessionPresent = true; // the sign-out did not clear the session
        await cubit.handleSignedOut();
      },
      expect: () => [
        KioskSessionState(status: KioskStatus.active, deadline: deadline),
      ],
      verify: (_) => verifyNever(() => store.clear()),
    );
  });

  group('runway timers', () {
    test('idle at lockout (T+11h45) signs out 15 minutes early', () {
      fakeAsync((async) {
        final cubit = build();
        cubit.enterKiosk();
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
        cubit.enterKiosk();
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

  group('restore (boot)', () {
    test('persisted + now < deadline → active with the remaining runway',
        () async {
      final future = t0.add(const Duration(hours: 6));
      when(() => store.read()).thenAnswer((_) async => (true, future));
      final cubit = build();
      await pumpEventQueue();
      expect(cubit.state.status, KioskStatus.active);
      expect(cubit.state.deadline, future);
      expect(signOutCalls, 0);
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

    test('no persisted flag → stays inactive', () async {
      final cubit = build();
      await pumpEventQueue();
      expect(cubit.state.status, KioskStatus.inactive);
      expect(signOutCalls, 0);
      await cubit.close();
    });
  });
}
