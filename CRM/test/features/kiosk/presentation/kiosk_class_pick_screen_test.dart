import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_class_pick_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

class _MockKioskFlowCubit extends MockCubit<KioskFlowState>
    implements KioskFlowCubit {}

/// The class pick is the screen the founder actually got stuck on: a member
/// who taps the WRONG name on home lands here, and before the escape existed
/// there was no way back — they were stranded until the 5-minute flow-idle
/// guard fired. These prove the escape is present, worded off the member's own
/// name, and routed through the ONE abandon path.
void main() {
  const member = AllViewRow(
    memberId: 'mem-1',
    name: 'Marcus Bell',
    membershipStatus: MembershipStatus.active,
    membershipText: 'Monthly',
  );

  final occurrence = EffectiveClassInstance(
    classId: 'class-1',
    gymId: 'gym-1',
    className: 'Muay Thai Fundamentals',
    classDate: DateTime(2026, 1, 1),
    originalDate: DateTime(2026, 1, 1),
    originalTime: '18:00:00',
    occurredAt: DateTime.utc(2026, 1, 1, 18),
    resolvedClassTime: '18:00:00',
    resolvedDurationMinutes: 60,
    pointsWorth: 15,
    isCancelled: false,
    hasInstanceException: false,
    hasRangeException: false,
  );

  Future<_MockKioskFlowCubit> pumpPick(
    WidgetTester tester,
    KioskFlowState state,
  ) async {
    final cubit = _MockKioskFlowCubit();
    whenListen(
      cubit,
      const Stream<KioskFlowState>.empty(),
      initialState: state,
    );
    addTearDown(cubit.close);
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<KioskFlowCubit>.value(
            value: cubit,
            child: const KioskClassPickScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    return cubit;
  }

  KioskFlowState pickState({List<EffectiveClassInstance>? classes}) =>
      KioskFlowState(
        view: KioskView.classPick,
        selectedMember: member,
        classes: classes ?? [occurrence],
      );

  testWidgets('the escape names the MEMBER, not the navigation', (tester) async {
    // The head one line above asserts "Hi Marcus, pick your class". The escape
    // has to answer that assertion, so it carries the member's FIRST name —
    // a member who is not Marcus reads their own situation in the button,
    // where "Back" would make them work out what "back" means.
    await pumpPick(tester, pickState());

    expect(find.text('Hi Marcus, pick your class'), findsOneWidget);
    expect(find.text('Not Marcus?'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('the escape is the quietest tier — never a call to action',
      (tester) async {
    await pumpPick(tester, pickState());

    // Ghost tier only: no primary and no outline button competes with it on
    // this screen, so a mis-tap can never land on the loud thing.
    expect(find.byType(KioskGhostButton), findsOneWidget);
    expect(find.byType(KioskPrimaryButton), findsNothing);
    expect(find.byType(KioskOutlineButton), findsNothing);
  });

  testWidgets('tapping it routes through goHome — the ONE abandon path',
      (tester) async {
    // goHome already IS the abandon contract (timers cancelled, in-flight
    // fetches dropped by the seq bumps, endFlow balanced, fresh home emitted).
    // A hand-rolled navigation here would leak the session's flow count.
    final cubit = await pumpPick(tester, pickState());

    await tester.tap(find.text('Not Marcus?'));
    await tester.pump();

    verify(() => cubit.goHome()).called(1);
  });

  testWidgets('the escape stays ON the fold — a tall class grid scrolls '
      'beneath it, never past it', (tester) async {
    // The whole point of an escape hatch is that it is reachable without
    // hunting. A stage that scrolled the foot away with the content would
    // strand exactly the flustered member it exists for. The stage pins the
    // foot and scrolls only the content beneath it.
    final many = [
      for (var i = 0; i < 6; i++)
        EffectiveClassInstance(
          classId: 'class-$i',
          gymId: 'gym-1',
          className: 'Class $i',
          classDate: DateTime(2026, 1, 1),
          originalDate: DateTime(2026, 1, 1),
          originalTime: '18:00:00',
          occurredAt: DateTime.utc(2026, 1, 1, 18),
          resolvedClassTime: '18:00:00',
          resolvedDurationMinutes: 60,
          pointsWorth: 15,
          isCancelled: false,
          hasInstanceException: false,
          hasRangeException: false,
        ),
    ];
    await pumpPick(tester, pickState(classes: many));

    final foot = tester.getRect(find.text('Not Marcus?'));
    expect(foot.bottom, lessThanOrEqualTo(820));
    // And it is genuinely hittable where it sits, with no scrolling first.
    await tester.tap(find.text('Not Marcus?'));
    await tester.pump();
  });

  testWidgets('the escape survives the empty and failed class states', (
    tester,
  ) async {
    // The stranded member is MOST likely on a screen with nothing to tap: no
    // classes open, or the load failed. The way out cannot depend on the grid.
    await pumpPick(tester, pickState(classes: const []));
    expect(find.text('Not Marcus?'), findsOneWidget);

    await pumpPick(
      tester,
      pickState(classes: const []).copyWith(classesFailed: true),
    );
    expect(find.text('Not Marcus?'), findsOneWidget);
  });

  testWidgets('an unknown name degrades to the shared fallback, never a blank',
      (tester) async {
    await pumpPick(
      tester,
      const KioskFlowState(view: KioskView.classPick),
    );

    expect(find.text('Not there?'), findsOneWidget);
  });
}
