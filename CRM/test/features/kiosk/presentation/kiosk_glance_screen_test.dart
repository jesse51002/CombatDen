import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mocktail/mocktail.dart';
import 'package:theme_flutter/theme/animation/scale_reveal.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/check_in/data/models/check_in_response.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_glance_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_greeting.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_lift.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_reward_tile.dart';
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

  /// Runs the whole choreography out and lets everything come to rest.
  ///
  /// `pumpAndSettle` alone is not enough: the beats are `Future.delayed`
  /// timers, and between the confirmation's fade landing and the panels beat
  /// firing there is a stretch with no animation running at all — no scheduled
  /// frame, so `pumpAndSettle` would return mid-choreography and the test
  /// would end on a pending timer. Jumping the clock past the last beat (and
  /// the tile cascade behind it) closes that gap.
  Future<void> settleReveal(WidgetTester tester) async {
    await tester.pump(
      kKioskGlanceLastBeat + KioskRevealTimings.tileStagger * 4,
    );
    await tester.pumpAndSettle();
  }

  // Balance 2,150: the 1,000 reward is affordable (ready), the 2,500 is not.
  final glanceState = KioskFlowState(
    view: KioskView.checkedIn,
    selectedMember: member,
    selectedClassName: 'Muay Thai Fundamentals',
    checkInResult: recorded,
    pointsBalance: 2150,
    rewards: [reward('a', 1000), reward('b', 2500)],
    glanceCountdown: 10,
  );

  /// Mounts the glance. [reduceMotion] drives the accessibility flag the whole
  /// reveal keys off; [settle] pumps past the choreography (off for the tests
  /// that inspect a beat mid-flight).
  Future<_MockKioskFlowCubit> pumpGlance(
    WidgetTester tester,
    KioskFlowState state, {
    bool reduceMotion = false,
    bool settle = true,
    Stream<KioskFlowState> states = const Stream<KioskFlowState>.empty(),
  }) async {
    // The rewards panel's app nudge is WHITE-LABELLED off the active gym —
    // the same source the kiosk header names it from.
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Iron Den',
      role: EmployeeRole.owner,
      timezone: 'America/Chicago',
      logoUrl: null,
    );
    final cubit = _MockKioskFlowCubit();
    whenListen(cubit, states, initialState: state);
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
      await settleReveal(tester);
    } else {
      await tester.pump();
    }
    return cubit;
  }

  /// The opacity the reveal is currently holding [text] at. The reveal wrapper
  /// is the nearest thing above a beat's own text that introduces an
  /// [Opacity], so it IS that beat's entrance.
  ///
  /// `find.text(...).first` matters: while the confirmation is travelling it
  /// exists twice (the slot copy reserving its space, and the copy in flight —
  /// see `KioskGlanceLift`). Both carry the same `KioskReveal`, mounted on the
  /// same frame, so either answers for the fade; naming the first keeps the
  /// finder unambiguous.
  double revealOpacity(WidgetTester tester, String text) {
    return tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.text(text).first,
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
  }

  /// How far the (single, settled) confirmation's vertical centre sits from
  /// the vertical centre of the whole glance column.
  double confirmationOffsetFromCentre(
    WidgetTester tester,
    Finder confirmation,
  ) {
    final glance = tester.getRect(find.byType(KioskGlanceLift));
    return tester.getRect(confirmation).center.dy - glance.center.dy;
  }

  testWidgets('renders the glance with no layout error at iPad-landscape size',
      (tester) async {
    await pumpGlance(tester, glanceState);

    expect(tester.takeException(), isNull);
    expect(find.text('Checked into Muay Thai Fundamentals'), findsOneWidget);
    expect(find.text('week streak'), findsOneWidget);
    expect(find.text('YOUR POINTS'), findsOneWidget);
    expect(find.text('+15 pts'), findsOneWidget);
    expect(find.text('Redeem rewards in the Iron Den app'), findsOneWidget);
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
    expect(find.text('Redeem rewards in the Iron Den app'), findsNothing);
    expect(find.text('Get the Iron Den app to book classes'), findsOneWidget);
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
    const line = 'Checked into Muay Thai Fundamentals';

    testWidgets('lands in two beats: the confirmation alone, then BOTH cards',
        (tester) async {
      // The order IS the information hierarchy: "did it work, and into what?"
      // is answered, alone, before anything is paid out — and then the payout
      // arrives as one pair rather than a queue. Each assertion is taken one
      // frame BEFORE the next beat is due, so it proves the later beat is
      // still invisible rather than merely later in the widget tree.
      await pumpGlance(tester, glanceState, settle: false);

      // One frame's worth of motion — a beat's controller only advances on the
      // frame AFTER its delay fires, so each crossing is pumped then ticked.
      const tick = Duration(milliseconds: 16);

      // Beat 1 is already fading in; beat 2 has not started.
      await tester.pump(tick);
      expect(revealOpacity(tester, line), greaterThan(0));
      expect(revealOpacity(tester, 'week streak'), 0);
      expect(revealOpacity(tester, 'YOUR POINTS'), 0);

      // A second and a half later the confirmation still has the screen to
      // itself — the founder's centred hold, the beat this re-time exists for.
      await tester.pump(KioskRevealTimings.centredHold);
      expect(revealOpacity(tester, 'week streak'), 0);
      expect(revealOpacity(tester, 'YOUR POINTS'), 0);

      // Not even the lift shows them: they wait for it to LAND.
      await tester.pump(KioskRevealTimings.lift - tick * 2);
      expect(revealOpacity(tester, 'week streak'), 0);
      expect(revealOpacity(tester, 'YOUR POINTS'), 0);

      // Beat 2 — and both cards cross together, to the frame. (A beat's
      // controller only starts on the frame after its delay fires, so the
      // crossing is pumped and then ticked.)
      await tester.pump(tick * 2);
      await tester.pump(tick);
      final streak = revealOpacity(tester, 'week streak');
      expect(streak, greaterThan(0));
      expect(revealOpacity(tester, 'YOUR POINTS'), streak);
      await settleReveal(tester);
    });

    testWidgets('the two cards ride ONE reveal — they can never desync',
        (tester) async {
      // The founder asked for both cards to pop at the same time. Two matching
      // offsets would satisfy that until someone nudged one of them, so the
      // row shares a single KioskReveal and this proves it: sampled through
      // the entrance, the two panels hold the exact same opacity.
      await pumpGlance(tester, glanceState, settle: false);
      await tester.pump(KioskRevealTimings.panels);

      for (var i = 0; i < 4; i++) {
        await tester.pump(KioskRevealTimings.element ~/ 5);
        expect(
          revealOpacity(tester, 'YOUR POINTS'),
          revealOpacity(tester, 'week streak'),
        );
      }
      await settleReveal(tester);
    });

    testWidgets('beat 1 is CENTRED and alone, and beat 2 only starts once it '
        'has landed at the top', (tester) async {
      // The founder's ruling: the check-in confirmation owns the middle of the
      // screen by itself, then travels up and hands over. Two things are
      // proven here — where it sits during the hold, and where it sits after.
      await pumpGlance(tester, glanceState, settle: false);
      await tester.pump(const Duration(milliseconds: 16));

      // In flight (and during the hold) the painted copy is the keyed one.
      final travelling = find.byKey(kKioskGlanceTravellingConfirmation);
      expect(travelling, findsOneWidget);
      expect(
        confirmationOffsetFromCentre(tester, travelling).abs(),
        lessThan(1),
        reason: 'the confirmation holds at the centre of the glance',
      );

      // Still centred one frame before it is due to move.
      await tester.pump(
        KioskRevealTimings.centredHold - const Duration(milliseconds: 32),
      );
      expect(
        confirmationOffsetFromCentre(tester, travelling).abs(),
        lessThan(1),
      );

      // Mid-travel it is genuinely between the two positions — a real move,
      // not a cut.
      await tester.pump(
        const Duration(milliseconds: 32) + KioskRevealTimings.lift ~/ 4,
      );
      final midFlight = confirmationOffsetFromCentre(tester, travelling);
      expect(midFlight, lessThan(0), reason: 'it is on its way UP');
      expect(midFlight.abs(), greaterThan(1));

      // Landed: the travelling copy is gone and the one confirmation left
      // sits at the very top of the glance column.
      await tester.pump(KioskRevealTimings.lift);
      expect(find.byKey(kKioskGlanceTravellingConfirmation), findsNothing);
      expect(find.text(line), findsOneWidget);
      expect(
        tester.getRect(find.byType(KioskGlanceGreeting)).top,
        moreOrLessEquals(
          tester.getRect(find.byType(KioskGlanceLift)).top,
          epsilon: 0.5,
        ),
      );
      await settleReveal(tester);
    });

    testWidgets('the choreography does NOT replay when the "Get the app" modal '
        'closes back onto a settled glance', (tester) async {
      // Done on the modal hands the member back to the glance with its hold
      // restarted at full — but the glance itself must stay exactly where they
      // left it. Replaying the confirmation lift (or re-rolling the streak)
      // would make a member who pressed Done watch the whole screen assemble
      // itself a second time.
      final states = StreamController<KioskFlowState>();
      addTearDown(states.close);
      await pumpGlance(tester, glanceState, states: states.stream);

      final greetingBefore = tester.getRect(find.byType(KioskGlanceGreeting));

      // The cubit restarts the hold at full on close — the only thing that
      // changes on the glance's own state.
      states.add(glanceState.copyWith(glanceCountdown: 10));
      await tester.pump();

      // No travelling copy: the lift did not start again.
      expect(find.byKey(kKioskGlanceTravellingConfirmation), findsNothing);
      // The confirmation is still landed in its slot, not back at the centre.
      expect(
        tester.getRect(find.byType(KioskGlanceGreeting)),
        greetingBefore,
      );
      // Both cards are still fully landed, not re-fading from zero.
      expect(revealOpacity(tester, 'week streak'), 1);
      expect(revealOpacity(tester, 'YOUR POINTS'), 1);
      // And the streak numeral is its final value, not rolling up again.
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('the lift moves the confirmation ONLY — nothing else on the '
        'glance shifts', (tester) async {
      // "Reserve the space" is the whole trick: the two cards and the footer
      // are laid out from the first frame, invisible, so no beat can reflow
      // the screen the member is reading — and Done never moves under a finger
      // that is already on its way to it.
      await pumpGlance(tester, glanceState, settle: false);
      await tester.pump(const Duration(milliseconds: 16));

      final doneBefore = tester.getRect(find.text('Done'));
      final columnBefore = tester.getRect(find.byType(KioskGlanceLift));
      final cardsBefore = [
        tester.getRect(find.text('week streak')),
        tester.getRect(find.text('YOUR POINTS')),
      ];

      await settleReveal(tester);

      // Not a pixel: had the cards not been holding their space, the column
      // would have been short here and the footer would have jumped down when
      // they arrived.
      expect(tester.getRect(find.text('Done')), doneBefore);
      expect(tester.getRect(find.byType(KioskGlanceLift)), columnBefore);

      // The cards themselves only ever travel their own entrance rise (the
      // shared 12px `StaggeredReveal` slide, which is paint, not layout) —
      // never a reflow, and never sideways.
      final cardsAfter = [
        tester.getRect(find.text('week streak')),
        tester.getRect(find.text('YOUR POINTS')),
      ];
      for (final (index, after) in cardsAfter.indexed) {
        final before = cardsBefore[index];
        expect(after.left, before.left);
        expect(after.width, before.width);
        expect(before.top - after.top, inInclusiveRange(0, 16));
      }
    });

    testWidgets('Done still works while the confirmation is centred',
        (tester) async {
      // A member must be able to leave at any point in the ~12 seconds, not be
      // held hostage by the choreography. The travelling copy covers the whole
      // glance while it is in flight, so it must not eat the tap.
      final cubit = await pumpGlance(tester, glanceState, settle: false);
      await tester.pump(KioskRevealTimings.centredHold ~/ 2);
      expect(find.byKey(kKioskGlanceTravellingConfirmation), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pump();

      verify(() => cubit.goHome()).called(1);
      verifyNever(() => cubit.openAppModal());
      await settleReveal(tester);
    });

    testWidgets('the confirmation FADES IN — it is never simply present',
        (tester) async {
      // It was the one element with no entrance of its own, which is what made
      // the glance read as a hard cut even with everything below it animating.
      await pumpGlance(tester, glanceState, settle: false);

      expect(revealOpacity(tester, line), lessThan(1));

      await tester.pump(KioskRevealTimings.confirmationFade);
      expect(revealOpacity(tester, line), 1);
      await settleReveal(tester);
    });

    testWidgets('the streak numeral counts UP rather than appearing',
        (tester) async {
      await pumpGlance(tester, glanceState, settle: false);

      // Mid-roll the reel is somewhere below the target; only at the end does
      // the final number stand alone.
      await tester.pump(KioskRevealTimings.panels);
      expect(find.byType(CountUpText), findsOneWidget);

      await tester.pump(KioskRevealTimings.countUp);
      expect(find.text('7'), findsWidgets);
      await settleReveal(tester);
    });

    testWidgets('the beat sheet keeps the shape the founder set',
        (tester) async {
      // Two beats: a second and a half of the confirmation alone, then both
      // cards the moment it lands. Nothing here may quietly drift back into a
      // one-at-a-time cascade or a longer wait.
      expect(
        KioskRevealTimings.centredHold,
        const Duration(milliseconds: 1500),
      );
      expect(
        KioskRevealTimings.panels,
        KioskRevealTimings.centredHold + KioskRevealTimings.lift,
        reason: 'the cards show once the confirmation has LANDED',
      );
      // The confirmation is fully read before it moves.
      expect(
        KioskRevealTimings.confirmationFade,
        lessThan(KioskRevealTimings.centredHold),
      );
      // The order the screen depends on holds in the constants too.
      expect(
        KioskRevealTimings.confirmation,
        lessThan(KioskRevealTimings.panels),
      );
    });

    testWidgets('the 10-second hold starts at the LAST beat, and the reward '
        'cascade is over early inside it', (tester) async {
      // The contract between the choreography and the cubit: the cubit waits
      // out kKioskGlanceLastBeat before the hold clock ticks, so that constant
      // has to BE the last beat. The tiles then cascade inside the hold's
      // opening moments, leaving the bulk of it on a screen that has stopped
      // moving.
      expect(
        kKioskGlanceLastBeat,
        KioskRevealTimings.panels,
        reason: 'the hold must start when the last beat lands',
      );

      final cascade =
          KioskRevealTimings.tileStagger * (kKioskGlanceRewardCount - 1) +
              KioskRevealTimings.element;
      expect(
        cascade,
        lessThan(kKioskGlanceHold ~/ 4),
        reason: 'most of the hold must be reading time, not animation',
      );
      // The count-up rides the same beat and must also land well inside it.
      expect(KioskRevealTimings.countUp, lessThan(kKioskGlanceHold ~/ 4));
      // Slower than the old ripple: the tiles are meant to read as four
      // separate arrivals.
      expect(
        KioskRevealTimings.tileStagger,
        greaterThan(KioskRevealTimings.element ~/ 2),
      );
    });

    testWidgets('the reward tiles cascade INSIDE their card, not behind it',
        (tester) async {
      // The trap: a KioskReveal delay runs from mount, and the reward grid
      // mounts as soon as the catalog lands — long before the panels beat. A
      // bare per-index stagger would therefore play out under a card that is
      // still invisible, and the member would see four tiles simply present.
      await pumpGlance(tester, glanceState, settle: false);

      // The card has just landed; the second tile has NOT arrived yet.
      await tester.pump(KioskRevealTimings.panels);
      await tester.pump(const Duration(milliseconds: 16));
      final tiles = tester
          .widgetList<KioskRewardTile>(find.byType(KioskRewardTile))
          .length;
      expect(tiles, 2);
      expect(revealOpacity(tester, 'Reward a'), greaterThan(0));
      expect(revealOpacity(tester, 'Reward b'), 0);

      // It arrives one stagger slot later (crossed, then ticked).
      await tester.pump(KioskRevealTimings.tileStagger);
      await tester.pump(const Duration(milliseconds: 16));
      expect(revealOpacity(tester, 'Reward b'), greaterThan(0));
      await settleReveal(tester);
    });
  });

  group('reduced motion', () {
    testWidgets('shows the whole glance immediately — no stagger, no roll',
        (tester) async {
      // Precedent: the kiosk showcase rotation already honors this flag. A
      // viewer who asked for less motion must never sit in front of a screen
      // that is half-empty for two seconds because a choreography they cannot
      // see is still playing out.
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

    testWidgets('there is no centred hold — the confirmation is at its FINAL '
        'position on the first frame', (tester) async {
      // The lift is motion too. A reduced-motion viewer gets the landed
      // layout: no travelling copy, no centred hold at an off-position, and
      // nothing to wait out — while the cubit's ten-second hold still applies,
      // so there is time to read.
      await pumpGlance(
        tester,
        glanceState,
        reduceMotion: true,
        settle: false,
      );

      expect(find.byKey(kKioskGlanceTravellingConfirmation), findsNothing);
      expect(
        tester.getRect(find.byType(KioskGlanceGreeting)).top,
        moreOrLessEquals(
          tester.getRect(find.byType(KioskGlanceLift)).top,
          epsilon: 0.5,
        ),
      );
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
