import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mocktail/mocktail.dart';
import 'package:theme_flutter/theme/animation/scale_reveal.dart';

import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_glance_screen.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/shared/widgets/animation/count_up_text.dart';
import 'package:crm/shared/widgets/animation/staggered_reveal.dart';
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
    selectedClassName: 'Muay Thai Fundamentals',
    checkInResult: recorded,
    pointsBalance: 2150,
    rewards: [reward('a', 1000), reward('b', 2500)],
    glanceCountdown: 8,
  );

  /// Mounts the glance. [reduceMotion] drives the accessibility flag the whole
  /// reveal keys off; [settle] pumps past the choreography (off for the tests
  /// that inspect a beat mid-flight).
  Future<_MockKioskFlowCubit> pumpGlance(
    WidgetTester tester,
    KioskFlowState state, {
    bool reduceMotion = false,
    bool settle = true,
  }) async {
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
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: BlocProvider<KioskFlowCubit>.value(
              value: cubit,
              child: const KioskGlanceScreen(),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      // Past the whole reveal, then let the drain bar's 1s tween finish.
      await tester.pump(kKioskGlanceRevealSettle);
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return cubit;
  }

  /// The opacity the reveal is currently holding [text] at. The reveal wrapper
  /// is the only thing on the glance that introduces an [Opacity], so the
  /// nearest one above a beat's own text IS that beat's entrance.
  double revealOpacity(WidgetTester tester, String text) {
    return tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Opacity))
              .first,
        )
        .opacity;
  }

  testWidgets('renders the glance with no layout error at iPad-landscape size',
      (tester) async {
    await pumpGlance(tester, glanceState);

    expect(tester.takeException(), isNull);
    expect(find.text('Checked into Muay Thai Fundamentals'), findsOneWidget);
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

  testWidgets('a no-rewards gym still gets an app nudge — booking, not '
      'redeeming — over the points-only panel', (tester) async {
    await pumpGlance(
      tester,
      glanceState.copyWith(rewards: const <RewardResponse>[]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('YOUR POINTS'), findsOneWidget);
    expect(find.byType(ProgressArc), findsNothing);
    // The redeem line is gone but the funnel is not — it points at booking.
    expect(find.text('Redeem rewards in the CombatDen app'), findsNothing);
    expect(find.text('Get the CombatDen app to book classes'), findsOneWidget);
  });

  testWidgets('a repeat check-in says so and drops the +pts chip',
      (tester) async {
    // Contract-wise a repeat awards no points; the fixture keeps points to
    // prove the chip is suppressed by alreadyCheckedIn, not merely by a zero.
    const repeat = CheckInResponse(
      logId: 'log-1',
      memberId: 'mem-1',
      classId: 'class-1',
      alreadyCheckedIn: true,
      pointsAwarded: 15,
      classStreakWeeks: 7,
    );
    await pumpGlance(tester, glanceState.copyWith(checkInResult: repeat));

    expect(tester.takeException(), isNull);
    expect(
      find.text('Already checked into Muay Thai Fundamentals'),
      findsOneWidget,
    );
    expect(find.text('Checked into Muay Thai Fundamentals'), findsNothing);
    expect(find.text('+15 pts'), findsNothing);
  });

  testWidgets('the confirmation is ONE line — a fact, with nothing under it',
      (tester) async {
    // Founder ruling: at this instant the member wants to know whether it
    // worked and into what. A congratulatory second line adds no information
    // and delays the answer; the celebration is the streak + rewards below.
    await pumpGlance(tester, glanceState);

    expect(find.textContaining('Nice one'), findsNothing);
    expect(find.textContaining('Marcus'), findsNothing);
  });

  testWidgets('an unknown class degrades to the bare fact, never a blank',
      (tester) async {
    await pumpGlance(
      tester,
      glanceState.copyWith(selectedClassName: null),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Checked in'), findsOneWidget);
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

  group('the reveal choreography', () {
    testWidgets('lands in order: confirmation, then streak, then rewards',
        (tester) async {
      // The order IS the information hierarchy: "did it work, and into what?"
      // is answered before anything is paid out. Each assertion is taken one
      // frame BEFORE the next beat is due, so it proves the later beat is
      // still invisible rather than merely later in the widget tree.
      await pumpGlance(tester, glanceState, settle: false);

      // One frame's worth of motion — a beat's controller only advances on the
      // frame AFTER its delay fires, so each crossing is pumped then ticked.
      const tick = Duration(milliseconds: 16);

      // Beat 1 is already fading in; beats 2 and 3 have not started.
      await tester.pump(tick);
      expect(
        revealOpacity(tester, 'Checked into Muay Thai Fundamentals'),
        greaterThan(0),
      );
      expect(revealOpacity(tester, 'week streak'), 0);
      expect(revealOpacity(tester, 'YOUR POINTS'), 0);

      // Beat 2 is under way; beat 3 still has not started.
      await tester.pump(KioskRevealTimings.streak);
      await tester.pump(tick);
      expect(revealOpacity(tester, 'week streak'), greaterThan(0));
      expect(revealOpacity(tester, 'YOUR POINTS'), 0);

      // Beat 3 arrives last.
      await tester.pump(KioskRevealTimings.rewards);
      await tester.pump(tick);
      expect(revealOpacity(tester, 'YOUR POINTS'), greaterThan(0));

      // Everything has landed by the time the dwell clock is allowed to start.
      await tester.pump(kKioskGlanceRevealSettle);
      expect(revealOpacity(tester, 'YOUR POINTS'), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('the confirmation FADES IN — it is never simply present',
        (tester) async {
      // It was the one element with no entrance of its own, which is what made
      // the glance read as a hard cut even with everything below it animating.
      await pumpGlance(tester, glanceState, settle: false);

      const line = 'Checked into Muay Thai Fundamentals';
      expect(revealOpacity(tester, line), lessThan(1));

      await tester.pump(KioskRevealTimings.confirmationFade);
      expect(revealOpacity(tester, line), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('the streak numeral counts UP rather than appearing',
        (tester) async {
      await pumpGlance(tester, glanceState, settle: false);

      // Mid-roll the reel is somewhere below the target; only at the end does
      // the final number stand alone.
      await tester.pump(KioskRevealTimings.streak);
      expect(find.byType(CountUpText), findsOneWidget);

      await tester.pump(KioskRevealTimings.countUp);
      expect(find.text('7'), findsWidgets);
      await tester.pumpAndSettle();
    });

    testWidgets('every beat has settled inside the dwell-start window',
        (tester) async {
      // The contract between the choreography and the cubit: the 8-second
      // dwell waits out kKioskGlanceRevealSettle, so nothing may still be
      // moving at that mark or the member reads a screen that is still
      // assembling itself.
      final lastBeat = [
        KioskRevealTimings.confirmation + KioskRevealTimings.confirmationFade,
        KioskRevealTimings.streak + KioskRevealTimings.element,
        KioskRevealTimings.streak + KioskRevealTimings.countUp,
        KioskRevealTimings.rewards +
            KioskRevealTimings.tileStagger * (kKioskGlanceRewardCount - 1) +
            KioskRevealTimings.element,
      ].reduce((a, b) => a > b ? a : b);

      expect(
        lastBeat,
        lessThanOrEqualTo(kKioskGlanceRevealSettle),
        reason: 'the reveal must finish before the dwell clock starts',
      );
      // And the order the screen depends on holds in the constants too.
      expect(
        KioskRevealTimings.confirmation,
        lessThan(KioskRevealTimings.streak),
      );
      expect(KioskRevealTimings.streak, lessThan(KioskRevealTimings.rewards));
    });
  });

  group('reduced motion', () {
    testWidgets('shows the whole glance immediately — no stagger, no roll',
        (tester) async {
      // Precedent: the kiosk showcase rotation already honors this flag. A
      // viewer who asked for less motion must never sit in front of a screen
      // that is blank for two seconds because a cascade they cannot see is
      // still running.
      await pumpGlance(
        tester,
        glanceState,
        reduceMotion: true,
        settle: false,
      );

      // One frame in, everything is on screen at full opacity.
      expect(
        find.text('Checked into Muay Thai Fundamentals'),
        findsOneWidget,
      );
      expect(find.text('week streak'), findsOneWidget);
      expect(find.text('YOUR POINTS'), findsOneWidget);
      // Not a fast cascade — no cascade at all.
      expect(find.byType(StaggeredReveal), findsNothing);
      expect(find.byType(ScaleReveal), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('the streak shows its FINAL number straight away',
        (tester) async {
      await pumpGlance(
        tester,
        glanceState,
        reduceMotion: true,
        settle: false,
      );

      expect(find.byType(CountUpText), findsNothing);
      expect(find.text('7'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('a tap on the glance opens the get-the-app modal (not goHome)',
      (tester) async {
    // The founder's UX-5 ruling: the glance tap now funnels to the app modal
    // instead of ejecting home. Tapping an inert glance element (the streak
    // caption) routes to the glance's opaque gesture, not the Done button.
    final cubit = await pumpGlance(tester, glanceState);

    await tester.tap(find.text('week streak'));
    await tester.pump();

    verify(() => cubit.openAppModal()).called(1);
    verifyNever(() => cubit.goHome());
  });
}
