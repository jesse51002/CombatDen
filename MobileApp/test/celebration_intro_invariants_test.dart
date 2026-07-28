import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/formats/format_store.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/core/formats/theme_motion.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_body.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_day_badge.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_week_strip.dart';
import 'package:mobile_app/shared/widgets/animation/capture_reveal_clock.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_figure.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_stage.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_cta.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_stage.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// The functional-equivalence gate for `celebration_intro`.
///
/// A motion format may change TIMING AND ENTRANCE ONLY. It may not
/// change which elements exist, what the card is fed, or the app's
/// motion law. This asserts all three mechanically, for every value:
///
/// * **Same element set.** Every value is driven to its settled state
///   and its rendered content compared against one contract. An intro
///   may delay an element; it may never delete one.
/// * **Same controller contract.** CTA hidden and inert while the intro
///   plays, live once `markDone` lands, `markDone` fired exactly once
///   for every value — `none` included, because a card that never
///   finishes is a card with no CTA.
/// * **Same motion law.** No value's curve overshoots: sampled
///   numerically off each value's own frame function, and backed by a
///   source scan so an overshoot cannot re-enter through a curve the
///   frame model does not carry.
///
/// Pumped at real phone size, because a stage that only overflows once
/// a real body's height is in it would otherwise pass unnoticed.
void main() {
  tearDown(() {
    FormatStore.instance.reset();
    captureRevealClock.value = null;
  });

  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// Pin the tenant slot, exactly as the dev picker does at runtime.
  void pin(CelebrationIntro intro) {
    FormatStore.instance.set(CombatDenSlots.celebrationIntro, intro.name);
  }

  Widget card({
    PostClassController? controller,
    CelebrationFormat? format,
    VoidCallback? onCtaPressed,
  }) {
    return DefaultAssetBundle(
      bundle: StubAssetBundle(),
      child: MaterialApp(
        home: PostClassScaffold(
          formatOverride: format,
          controller: controller,
          body: StreakBody(stats: mockStreakStats, controller: controller),
          ctaLabel: 'Continue',
          onCtaPressed: onCtaPressed ?? () {},
          onClose: () {},
        ),
      ),
    );
  }

  double ctaOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(CelebrationCta),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  bool ctaIgnoresTaps(WidgetTester tester) => tester
      .widget<IgnorePointer>(
        find
            .descendant(
              of: find.byType(CelebrationCta),
              matching: find.byType(IgnorePointer),
            )
            .first,
      )
      .ignoring;

  /// Every string the card's own area renders, sorted. The count-up is a
  /// digit reel, so its cells are part of the set — which is the point:
  /// the comparison is over what is actually in the tree, not over a
  /// hand-written list of the elements someone remembered.
  List<String> stageTexts(WidgetTester tester) =>
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(CelebrationIntroStage),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .toList()
        ..sort();

  /// The settled streak card, derived from the mock rather than copied
  /// out of it, so a data change moves the contract with it.
  final settledContract = <String>[
    for (var i = 0; i <= mockStreakStats.weekCount; i++) '$i',
    'week streak',
    mockStreakStats.subtitle,
    ...mockStreakStats.weekDays.map((d) => d.label),
  ]..sort();

  void expectSettledCard(WidgetTester tester) {
    expect(stageTexts(tester), settledContract);
    expect(find.byType(CountUpText), findsOneWidget);
    expect(find.byType(StreakWeekStrip), findsOneWidget);
    expect(
      find.byType(StreakDayBadge),
      findsNWidgets(mockStreakStats.weekDays.length),
    );
    // The intro's figure is a transient. Once the card is settled it is
    // gone, for every value — including the ones that overlap.
    expect(find.byKey(CelebrationIntroFigure.heroKey), findsNothing);
  }

  /// Run the intro out and let the settled cascade land.
  Future<void> playOut(WidgetTester tester, CelebrationIntro intro) async {
    await tester.pump(
      introSpec(intro).total + const Duration(milliseconds: 50),
    );
    await tester.pump(const Duration(seconds: 4));
  }

  group('every value settles into the same element set', () {
    for (final intro in CelebrationIntro.values) {
      testWidgets('$intro', (tester) async {
        phoneSized(tester);
        pin(intro);
        await tester.pumpWidget(card());
        await playOut(tester, intro);

        expectSettledCard(tester);
      });
    }
  });

  group('the CTA is inert while the intro plays, live once it lands', () {
    for (final intro in CelebrationIntro.values) {
      testWidgets('$intro', (tester) async {
        phoneSized(tester);
        pin(intro);
        final controller = PostClassController();
        addTearDown(controller.dispose);
        var ctaTaps = 0;

        await tester.pumpWidget(
          card(controller: controller, onCtaPressed: () => ctaTaps++),
        );

        expect(controller.isAnimating, isTrue);
        expect(ctaOpacity(tester), 0);
        expect(ctaIgnoresTaps(tester), isTrue);

        await tester.tap(find.byType(AppPrimaryButton), warnIfMissed: false);
        await tester.pump();
        expect(ctaTaps, 0, reason: 'a hidden CTA must not be tappable');

        await playOut(tester, intro);

        expect(controller.isAnimating, isFalse);
        expect(ctaOpacity(tester), 1);
        expect(ctaIgnoresTaps(tester), isFalse);

        await tester.tap(find.byType(AppPrimaryButton));
        await tester.pump();
        expect(ctaTaps, 1);
      });
    }
  });

  group('markDone fires exactly once, for every value', () {
    for (final intro in CelebrationIntro.values) {
      testWidgets('$intro', (tester) async {
        phoneSized(tester);
        pin(intro);
        final controller = PostClassController();
        addTearDown(controller.dispose);
        var notifications = 0;
        controller.addListener(() => notifications++);

        await tester.pumpWidget(card(controller: controller));
        await playOut(tester, intro);

        expect(
          controller.isAnimating,
          isFalse,
          reason: '$intro never finished, so its card has no CTA',
        );
        expect(notifications, 1);

        // A late tap on a finished card must not re-fire it.
        await tester.tap(find.byType(CelebrationStage));
        await tester.pump();
        expect(notifications, 1);
      });
    }
  });

  group('a tap on the body reaches the final state', () {
    for (final intro in CelebrationIntro.values) {
      testWidgets('$intro', (tester) async {
        phoneSized(tester);
        pin(intro);
        final controller = PostClassController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(card(controller: controller));
        // One frame in: mid-intro for every value that has one.
        await tester.pump(const Duration(milliseconds: 16));

        await tester.tap(find.byType(CelebrationStage));
        await tester.pump();

        expect(controller.isAnimating, isFalse);
        expectSettledCard(tester);
        expect(ctaIgnoresTaps(tester), isFalse);

        // Drain the settled cascade's own delays.
        await tester.pump(const Duration(seconds: 4));
        expectSettledCard(tester);
      });
    }
  });

  group('the intro renders its figure and only its figure', () {
    for (final intro in CelebrationIntro.values) {
      testWidgets('$intro', (tester) async {
        phoneSized(tester);
        pin(intro);
        await tester.pumpWidget(card());
        await tester.pump(const Duration(milliseconds: 16));

        expect(
          find.byKey(CelebrationIntroFigure.heroKey),
          findsOneWidget,
          reason: '$intro must move a figure, not nothing',
        );
        // Exactly one figure: no value gets to open a second
        // celebration surface.
        expect(find.byType(CelebrationIntroFigure), findsOneWidget);

        await playOut(tester, intro);
      });
    }
  });

  group('no value overshoots its settled state', () {
    for (final intro in CelebrationIntro.values) {
      test('$intro', () {
        final spec = introSpec(intro);
        const steps = 400;
        const epsilon = 1e-9;

        for (var i = 0; i <= steps; i++) {
          final t = i / steps;
          final f = spec.frameAt(t);
          final at = 'at t=$t';

          // Scale never passes its settled size.
          expect(f.heroScale, lessThanOrEqualTo(1 + epsilon), reason: at);
          expect(f.heroScale, greaterThanOrEqualTo(-epsilon), reason: at);
          // Translation never passes its landing and comes back.
          expect(f.heroRise, greaterThanOrEqualTo(-epsilon), reason: at);
          expect(f.heroRise, lessThanOrEqualTo(1 + epsilon), reason: at);
          // Rotation never turns past square.
          expect(f.heroFlip, lessThanOrEqualTo(epsilon), reason: at);
          expect(
            f.heroFlip,
            greaterThanOrEqualTo(-math.pi / 2 - epsilon),
            reason: at,
          );
          // Opacity and the particle field stay inside their range.
          expect(f.heroOpacity, inInclusiveRange(-epsilon, 1 + epsilon),
              reason: at);
          expect(f.particleSpread, inInclusiveRange(-epsilon, 1 + epsilon),
              reason: at);
          expect(f.particleOpacity, inInclusiveRange(-epsilon, 1 + epsilon),
              reason: at);
        }
      });
    }
  });

  test('no intro authors a bounce, elastic, or anticipation curve', () {
    final dir = Directory('lib/shared/widgets/post_class/intro');
    expect(dir.existsSync(), isTrue, reason: 'the intro module moved');

    const banned = [
      'easeInBack',
      'easeOutBack',
      'easeInOutBack',
      'bounceIn',
      'bounceOut',
      'bounceInOut',
      'elasticIn',
      'elasticOut',
      'elasticInOut',
      'ElasticInCurve',
      'ElasticOutCurve',
      'ElasticInOutCurve',
      'BounceInCurve',
    ];

    final files = dir.listSync().whereType<File>().toList();
    expect(files, isNotEmpty);
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final curve in banned) {
        expect(
          source.contains(curve),
          isFalse,
          reason: '${file.path} reaches for $curve; the motion law is '
              'ease-out only',
        );
      }
    }
  });

  group('every value holds its timing contract', () {
    test('the switch is wired to the value it claims', () {
      for (final intro in CelebrationIntro.values) {
        expect(introSpec(intro).value, intro);
      }
    });

    test('burst is the shortest value', () {
      final shortest = CelebrationIntro.values
          .map(introSpec)
          .reduce((a, b) => a.total <= b.total ? a : b);
      expect(shortest.value, CelebrationIntro.burst);
    });

    test('only the values that declare a field render particles', () {
      expect(introSpec(CelebrationIntro.rise).particleRadii, isEmpty);
      expect(introSpec(CelebrationIntro.flipCount).particleRadii, isEmpty);
      expect(introSpec(CelebrationIntro.orbit).particleRadii, isNotEmpty);
      expect(introSpec(CelebrationIntro.burst).particleRadii, isNotEmpty);
    });
  });

  /// Values are allowed to differ in length — `burst` SHOULD be punchier
  /// than `orbit`. What is not allowed is motion the viewer cannot
  /// process. Both floors below are the legibility rule, not a parity
  /// rule.
  group('every value is long enough to read', () {
    /// A post-class intro is a composed moment: a run-up, the event,
    /// and a beat to take in what happened. The app's own per-element
    /// budget is 300ms (PRODUCT.md), so three beats plus the pause
    /// between them cannot fit under about a second and a half — below
    /// that the beats collapse into a single flash.
    const floor = Duration(milliseconds: 1500);

    /// Nothing may be fully committed on screen before this: the eye
    /// needs to catch the run-up starting, or the payoff arrives
    /// unannounced and reads as a glitch.
    const leadIn = Duration(milliseconds: 350);
    const committed = 0.5;

    for (final intro in CelebrationIntro.values) {
      test('$intro runs at least ${floor.inMilliseconds}ms', () {
        expect(
          introSpec(intro).total,
          greaterThanOrEqualTo(floor),
          reason: '$intro is too quick to perceive as a moment',
        );
      });

      test('$intro holds a lead-in before it commits', () {
        final spec = introSpec(intro);
        final steps = spec.total.inMilliseconds;
        for (var ms = 0; ms <= leadIn.inMilliseconds; ms++) {
          final f = spec.frameAt(ms / steps);
          expect(
            f.heroOpacity,
            lessThan(committed),
            reason: '$intro slams its figure on screen at ${ms}ms',
          );
          expect(
            f.particleOpacity,
            lessThan(committed),
            reason: '$intro slams its particles on screen at ${ms}ms',
          );
        }
      });
    }
  });

  group('a retired or unknown value falls back to what ships', () {
    // The backend may still send `none`, which used to be a value. The
    // parser resolves anything it does not recognise to the first value,
    // and that is now load-bearing rather than incidental.
    for (final wire in ['none', 'nonsense', '', 'Orbit']) {
      test('"$wire"', () {
        FormatStore.instance.set(CombatDenSlots.celebrationIntro, wire);
        expect(ThemeMotion.celebrationIntro(), CelebrationIntro.orbit);
      });
    }
  });

  group('the capture clock drives every value deterministically', () {
    for (final intro in CelebrationIntro.values) {
      testWidgets('$intro', (tester) async {
        phoneSized(tester);
        pin(intro);
        final spec = introSpec(intro);
        final controller = PostClassController();
        addTearDown(controller.dispose);

        // The harness sets the clock before the tree mounts.
        captureRevealClock.value = Duration.zero;
        await tester.pumpWidget(card(controller: controller));

        {
          expect(find.byKey(CelebrationIntroFigure.heroKey), findsOneWidget);

          // Held at one instant, the frame does not move on its own —
          // the clip's speed is the harness's to set, not the widget's.
          captureRevealClock.value = spec.total ~/ 2;
          await tester.pump();
          final held = tester
              .widget<Opacity>(
                find
                    .ancestor(
                      of: find.byKey(CelebrationIntroFigure.heroKey),
                      matching: find.byType(Opacity),
                    )
                    .first,
              )
              .opacity;
          await tester.pump(const Duration(seconds: 1));
          final stillHeld = tester
              .widget<Opacity>(
                find
                    .ancestor(
                      of: find.byKey(CelebrationIntroFigure.heroKey),
                      matching: find.byType(Opacity),
                    )
                    .first,
              )
              .opacity;
          expect(stillHeld, held);

          // The harness owns the CTA for the whole clip: a
          // clock-driven intro never finishes itself.
          expect(controller.isAnimating, isTrue);
        }

        // Winding the clock past the end lands the settled card.
        captureRevealClock.value = spec.total + const Duration(seconds: 5);
        await tester.pump();
        expectSettledCard(tester);
      });
    }
  });

  /// The founder's complaint, as an assertion: an intro that lets the
  /// card settle while it is still playing reads as the card giving up
  /// on its own animation and jumping ahead, not as one composed
  /// moment. The intro owns the stage until it is done.
  ///
  /// This is the honest form of the invariant — stronger than checking
  /// where the settled card lands, because it says the settled card
  /// must not be there AT ALL yet.
  group('the intro owns the stage until it finishes', () {
    for (final intro in CelebrationIntro.values) {
      testWidgets('$intro', (tester) async {
        phoneSized(tester);
        pin(intro);
        final spec = introSpec(intro);
        final controller = PostClassController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(card(controller: controller));

        // Sampled across the whole run, not just at one instant: an
        // early hand-off anywhere in the intro is the bug.
        const samples = 12;
        for (var i = 1; i < samples; i++) {
          await tester.pump(spec.total ~/ samples);
          expect(
            find.byType(CountUpText),
            findsNothing,
            reason:
                '$intro settled its card ${i * 100 ~/ samples}% of the way '
                'through the intro, before the intro was done',
          );
          expect(find.byType(StreakWeekStrip), findsNothing, reason: '$intro');
          expect(
            find.byKey(CelebrationIntroFigure.heroKey),
            findsOneWidget,
            reason: '$intro dropped its figure before it finished',
          );
          expect(controller.isAnimating, isTrue, reason: '$intro');
        }

        // ...and once it IS done, the card is there and the figure is not.
        await playOut(tester, intro);
        expect(find.byType(CountUpText), findsOneWidget);
        expect(find.byType(StreakWeekStrip), findsOneWidget);
        expect(find.byKey(CelebrationIntroFigure.heroKey), findsNothing);
        expect(controller.isAnimating, isFalse);
      });
    }
  });

  /// A motion value may change WHEN the settled card appears, never
  /// WHERE. Kept alongside the ownership gate above: that one proves the
  /// card does not arrive early, this one proves it does not arrive
  /// somewhere else.
  ///
  /// This is the gate that would have caught the real defect. Under
  /// `figureTop` the stage is top-aligned, and `flipCount` — the one
  /// value whose figure and settled content are alive at the same time
  /// — was forcing the body to fill the stage, which swallowed that
  /// alignment and dropped the stat ~190pt down the screen.
  group('no value moves the settled card', () {
    for (final format in CelebrationFormat.values) {
      testWidgets('$format', (tester) async {
        final positions = <CelebrationIntro, Offset>{};

        for (final intro in CelebrationIntro.values) {
          phoneSized(tester);
          pin(intro);
          await tester.pumpWidget(card(format: format));
          await playOut(tester, intro);
          positions[intro] = tester.getTopLeft(find.byType(StreakWeekStrip));
          await tester.pumpWidget(const SizedBox());
          FormatStore.instance.reset();
        }

        final shipped = positions[CelebrationIntro.orbit];
        for (final entry in positions.entries) {
          expect(
            entry.value,
            shipped,
            reason:
                '${entry.key} settles the card at ${entry.value} under '
                '$format, but the shipped value settles it at $shipped — '
                'a motion format changed an arrangement',
          );
        }
      });
    }
  });

  group('every arrangement survives every intro', () {
    for (final format in CelebrationFormat.values) {
      for (final intro in CelebrationIntro.values) {
        testWidgets('$format / $intro', (tester) async {
          phoneSized(tester);
          pin(intro);
          final controller = PostClassController();
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            card(controller: controller, format: format),
          );
          await tester.pump();
          expect(find.byType(CelebrationStage), findsOneWidget);
          expect(find.byType(AppPrimaryButton), findsOneWidget);

          await playOut(tester, intro);
          expectSettledCard(tester);
          expect(controller.isAnimating, isFalse);
        });
      }
    }
  });
}
