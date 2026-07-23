import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_glance_screen.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/shared/widgets/progress_arc.dart';

class _MockKioskFlowCubit extends MockCubit<KioskFlowState>
    implements KioskFlowCubit {}

/// The post-check-in glance is the member-facing money screen. This proves it
/// lays out at iPad-landscape size with no exception (the greeting + two
/// `IntrinsicHeight` panels + reward grid + footer interplay is the fragile
/// part), renders the mockup's copy, and splits reward tiles into READY (a
/// filled disc) vs IN-PROGRESS (a ring) purely from the points balance.
void main() {
  final createdAt = DateTime.utc(2026, 1, 1);

  const member = AllViewRow(
    memberId: 'mem-1',
    name: 'Marcus Bell',
    membershipStatus: MembershipStatus.active,
    membershipText: 'Monthly',
  );

  const recorded = CheckInResponse(
    logId: 'log-1',
    memberId: 'mem-1',
    classId: 'class-1',
    alreadyCheckedIn: false,
    pointsAwarded: 15,
    classStreakWeeks: 7,
  );

  // Mon + Wed attended this week (Monday-first: index 0 = Mon, 2 = Wed).
  const monWed = CheckInResponse(
    logId: 'log-1',
    memberId: 'mem-1',
    classId: 'class-1',
    alreadyCheckedIn: false,
    pointsAwarded: 15,
    classStreakWeeks: 2,
    currentWeekDays: [true, false, true, false, false, false, false],
  );

  RewardResponse reward(String id, int cost) => RewardResponse(
        rewardId: id,
        gymId: 'gym-1',
        title: 'Reward $id',
        pointCost: cost,
        priceLabel: 'Free',
        // Null image -> the tile shows its placeholder (no network in tests).
        isActive: true,
        createdAt: createdAt,
      );

  // Balance 2,150: the 1,000 reward is affordable (ready), the 2,500 is not.
  final glanceState = KioskFlowState(
    view: KioskView.checkedIn,
    selectedMember: member,
    checkInResult: recorded,
    pointsBalance: 2150,
    rewards: [reward('a', 1000), reward('b', 2500)],
    glanceCountdown: 8,
  );

  Future<void> pumpGlance(WidgetTester tester, KioskFlowState state) async {
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
            child: const KioskGlanceScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // let the drain bar's 1s tween finish
  }

  testWidgets('renders the glance with no layout error at iPad-landscape size',
      (tester) async {
    await pumpGlance(tester, glanceState);

    expect(tester.takeException(), isNull);
    expect(find.text('Nice one, Marcus.'), findsOneWidget);
    expect(find.text('week streak'), findsOneWidget);
    expect(find.text('YOUR POINTS'), findsOneWidget);
    expect(find.text('+15 pts'), findsOneWidget);
    expect(find.text('Redeem rewards in the CombatDen app'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.textContaining('Back to start in'), findsOneWidget);
  });

  testWidgets('splits reward tiles into ready (disc) vs in-progress (ring) by '
      'balance', (tester) async {
    await pumpGlance(tester, glanceState);

    // The 2,500 reward (unaffordable) draws one progress ring.
    expect(find.byType(ProgressArc), findsOneWidget);
    // Two filled check discs: the greeting's + the one ready reward tile's.
    expect(find.byIcon(Symbols.check_sharp), findsNWidgets(2));
  });

  testWidgets('shows a points-only panel (no grid, no redeem line) when the '
      'gym has no rewards', (tester) async {
    await pumpGlance(
      tester,
      glanceState.copyWith(rewards: const <RewardResponse>[]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('YOUR POINTS'), findsOneWidget);
    expect(find.byType(ProgressArc), findsNothing);
    expect(find.text('Redeem rewards in the CombatDen app'), findsNothing);
  });

  testWidgets('week strip marks current_week_days positionally, Monday-first',
      (tester) async {
    await pumpGlance(tester, glanceState.copyWith(checkInResult: monWed));

    // The strip's badges are the ONLY circle/check-circle icons on the glance.
    // Widget-tree traversal walks the Row's children left-to-right, so the
    // icon order is Mon..Sun — proving the render is Monday-first, no reorder.
    final strip = tester
        .widgetList<Icon>(
          find.byWidgetPredicate(
            (w) =>
                w is Icon &&
                (w.icon == Symbols.check_circle_sharp ||
                    w.icon == Symbols.circle_sharp),
          ),
        )
        .toList();
    final completed = [
      for (final icon in strip) icon.icon == Symbols.check_circle_sharp,
    ];

    // Mon (0) + Wed (2) done; the other five open.
    expect(completed, [true, false, true, false, false, false, false]);
    expect(find.byIcon(Symbols.check_circle_sharp), findsNWidgets(2));
    expect(find.byIcon(Symbols.circle_sharp), findsNWidgets(5));
  });

  testWidgets('week strip falls back to all-open when no per-day data',
      (tester) async {
    // Default check-in response: currentWeekDays is a length-7 all-false list.
    await pumpGlance(tester, glanceState);

    expect(find.byIcon(Symbols.check_circle_sharp), findsNothing);
    expect(find.byIcon(Symbols.circle_sharp), findsNWidgets(7));
  });
}
