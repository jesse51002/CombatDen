import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/formats/format_store.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_body.dart';
import 'package:mobile_app/shared/widgets/animation/capture_reveal_clock.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_arc_painter.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_figure.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_frame.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_figure.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/intro_flip_count.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// The functional-equivalence gate for `count_up_style`.
///
/// A motion format may change TIMING AND ENTRANCE ONLY. For the earned
/// figure — the payoff of the whole post-class moment — that means a
/// value gets to change how the number arrives and nothing about what it
/// says, how much room it takes, or whether a person can read it. This
/// asserts all of that mechanically, for every value:
///
/// * **Same figure at rest.** Same final string, same prefix/suffix,
///   same thousands grouping, and the same number actually visible on
///   screen — read off the widgets each value chose, not off a
///   hand-written list.
/// * **Same box.** The settled size is identical across values, and
///   `sweepArc` never resizes its own box as it settles.
/// * **Same motion law.** No value overshoots, sampled numerically off
///   each value's own frame function, and the number reaches its target
///   exactly once — never past it and back. Backed by a source scan so
///   an overshoot cannot re-enter through a curve the frame model does
///   not carry.
/// * **Processable.** Every value that animates runs long enough, and
///   leads in late enough, that a person watches the figure arrive and
///   reads where it landed. `instant` is the sole exemption: "no
///   animation" and "an animation too fast to read" are different
///   things.
/// * **Deterministic under capture.** The capture clock drives every
///   value; none of them self-runs while it is set.
/// * **The `flipCount` hand-off still works.** That intro deliberately
///   starts the count mid-flip, so no value's lead-in may push the roll
///   out past the flip it overlaps.
void main() {
  // The figure the pumped tests use: two digits, a prefix and a suffix.
  const target = 42;
  const prefix = '+';
  const suffix = ' points';
  const settled = '+42 points';

  // Perception floors for a figure a person is meant to watch land.
  //
  // A saccade onto a newly-changing target plus the fixation needed to
  // recognise a numeral costs roughly 250-400ms, and reading the settled
  // figure needs another ~250ms of stable fixation. So the span over
  // which the figure is visibly changing must be long enough that the
  // eye can land mid-change and still have change left to perceive, and
  // the whole run must leave a readable tail after it.
  //
  // These are floors, not a band: values are free to differ in length.
  // What is banned is a value so quick the payoff is over before it is
  // seen.
  const arrivalFloor = Duration(milliseconds: 600);
  const totalFloor = Duration(milliseconds: 900);

  // Every value except the shipped one holds a beat before the number
  // starts moving, so the eye registers that something is about to
  // happen. `odometer` is exempt because it is the parse fallback: every
  // unbranded build and every tenant without the slot renders through
  // it, so adding a hold there would change what ships for all of them.
  const leadInFloor = Duration(milliseconds: 150);

  const steps = 400;
  const epsilon = 1e-9;

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
  void pin(CountUpStyle value) {
    FormatStore.instance.set(CombatDenSlots.countUpStyle, value.name);
  }

  Widget host({
    int figure = target,
    String lead = prefix,
    String tail = suffix,
    TextStyle? style,
    Duration delay = Duration.zero,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: CountUpText(
            target: figure,
            style: style ?? DesignConstants.big2,
            prefix: lead,
            suffix: tail,
            delay: delay,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// The count-up's accessible figure: one string for the whole number,
  /// which is the only rendering every value shares (a reel is a column
  /// of ten glyphs, not a number).
  Finder labelled(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  /// What one digit position is actually showing, in that slot's own
  /// units: a reel's fractional index, or the glyph a plain cell renders.
  double slotProbe(WidgetTester tester, int position) {
    final slot = find.byKey(CountUpFigure.slotKey(position));
    expect(slot, findsOneWidget, reason: 'position $position is missing');
    final reel = find.descendant(of: slot, matching: find.byType(Transform));
    if (reel.evaluate().isNotEmpty) {
      // storage[13] is the matrix's Y translation.
      final dy = tester.widget<Transform>(reel).transform.storage[13];
      return -dy / tester.getSize(slot).height;
    }
    final glyph = tester.widget<Text>(
      find.descendant(of: slot, matching: find.byType(Text)),
    );
    return double.parse(glyph.data!);
  }

  /// The whole number on screen, composed from what each position shows.
  int visibleNumber(WidgetTester tester, int figure, bool reeled) {
    var value = 0;
    for (var p = CountUpFigure.digitCountFor(figure) - 1; p >= 0; p--) {
      final raw = slotProbe(tester, p).round();
      value = value * 10 + (reeled ? raw % 10 : raw);
    }
    return value;
  }

  /// Every position's raw state — the probe used to prove nothing moves
  /// on its own while the capture clock holds.
  List<double> signature(WidgetTester tester, int figure) => [
    for (var p = 0; p < CountUpFigure.digitCountFor(figure); p++)
      slotProbe(tester, p),
  ];

  /// The first sampled instant, as a fraction of the run, at which
  /// [test] holds.
  double firstT(CountUpSpec spec, bool Function(CountUpFrame) test) {
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      if (test(spec.frameAt(t))) return t;
    }
    return double.nan;
  }

  Duration atFraction(CountUpSpec spec, double t) {
    final total = spec.totalFor(CelebrationTimings.countUpDuration);
    return Duration(microseconds: (total.inMicroseconds * t).round());
  }

  /// When the figure starts visibly moving.
  Duration leadInOf(CountUpSpec spec) =>
      atFraction(spec, firstT(spec, (f) => f.progress > 0.01));

  /// The span over which the figure is visibly changing.
  Duration arrivalOf(CountUpSpec spec) =>
      atFraction(spec, firstT(spec, (f) => f.progress >= 0.99)) -
      leadInOf(spec);

  group('every value settles into the same figure', () {
    for (final value in CountUpStyle.values) {
      testWidgets('$value', (tester) async {
        phoneSized(tester);
        pin(value);
        await tester.pumpWidget(host());
        await tester.pump(const Duration(seconds: 4));

        expect(find.byType(CountUpText), findsOneWidget);
        expect(labelled(settled), findsOneWidget);
        expect(
          visibleNumber(tester, target, countUpSpec(value).reeled),
          target,
          reason: '$value did not land on the earned figure',
        );
        expect(find.text(prefix), findsOneWidget);
        expect(find.text(suffix), findsOneWidget);
      });
    }
  });

  group('thousands grouping, prefix and suffix survive every value', () {
    for (final value in CountUpStyle.values) {
      testWidgets('$value', (tester) async {
        phoneSized(tester);
        pin(value);
        await tester.pumpWidget(
          host(figure: 1234, style: DesignConstants.h3),
        );
        await tester.pump(const Duration(seconds: 4));

        expect(labelled('+1,234 points'), findsOneWidget);
        expect(find.text(','), findsOneWidget);
        expect(visibleNumber(tester, 1234, countUpSpec(value).reeled), 1234);
      });
    }
  });

  testWidgets('the settled figure occupies the same box for every value', (
    tester,
  ) async {
    phoneSized(tester);
    final sizes = <CountUpStyle, Size>{};

    for (final value in CountUpStyle.values) {
      pin(value);
      await tester.pumpWidget(host());
      await tester.pump(const Duration(seconds: 4));
      sizes[value] = tester.getSize(find.byType(CountUpText));
    }

    final shipped = sizes[CountUpStyle.odometer]!;
    expect(shipped.width, greaterThan(0));
    for (final entry in sizes.entries) {
      expect(
        entry.value,
        shipped,
        reason: '${entry.key} settles into a different box than odometer, '
            'so it would shift everything around it',
      );
    }
  });

  testWidgets('sweepArc never resizes its own box', (tester) async {
    phoneSized(tester);
    pin(CountUpStyle.sweepArc);
    await tester.pumpWidget(host());

    final mounted = tester.getSize(find.byType(CountUpText));
    final samples = <Size>[];
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      samples.add(tester.getSize(find.byType(CountUpText)));
    }
    await tester.pump(const Duration(seconds: 4));
    samples.add(tester.getSize(find.byType(CountUpText)));

    for (final size in samples) {
      expect(
        size,
        mounted,
        reason: 'the arc changed the figure\'s layout size',
      );
    }
  });

  group('the capture clock drives every value deterministically', () {
    for (final value in CountUpStyle.values) {
      testWidgets('$value', (tester) async {
        phoneSized(tester);
        pin(value);
        final spec = countUpSpec(value);
        final total = spec.totalFor(CelebrationTimings.countUpDuration);

        // The harness sets the clock before the tree mounts.
        captureRevealClock.value = Duration.zero;
        await tester.pumpWidget(host());

        final atStart = signature(tester, target);
        await tester.pump(const Duration(seconds: 1));
        expect(
          signature(tester, target),
          atStart,
          reason: '$value self-runs while the capture clock is driving',
        );

        if (!spec.isInstant) {
          captureRevealClock.value = total ~/ 2;
          await tester.pump();
          final held = signature(tester, target);
          expect(held, isNot(atStart));

          // The clip's speed is the harness's to set, not the widget's.
          await tester.pump(const Duration(seconds: 1));
          expect(signature(tester, target), held);

          // And the state it holds is exactly the value's own frame.
          final frame = spec.frameAt(0.5);
          if (spec.reeled) {
            expect(
              slotProbe(tester, 0),
              closeTo(frame.progress * target, 1e-6),
            );
          } else {
            expect(
              visibleNumber(tester, target, false),
              frame.displayedValue(target),
            );
          }
        }

        captureRevealClock.value = total + const Duration(seconds: 5);
        await tester.pump();
        expect(visibleNumber(tester, target, spec.reeled), target);
        expect(labelled(settled), findsOneWidget);
      });
    }
  });

  group('the capture clock honours each figure\'s own delay', () {
    for (final value in CountUpStyle.values) {
      testWidgets('$value', (tester) async {
        phoneSized(tester);
        pin(value);
        final spec = countUpSpec(value);
        final total = spec.totalFor(CelebrationTimings.countUpDuration);
        const offset = Duration(milliseconds: 400);

        captureRevealClock.value = Duration.zero;
        await tester.pumpWidget(host(delay: offset));
        final beforeSlot = signature(tester, target);

        // On its slot on the global timeline the figure is exactly where
        // its own frame function starts it — which for `instant` is
        // already landed, and for the rest is zero.
        captureRevealClock.value = offset;
        await tester.pump();
        expect(signature(tester, target), beforeSlot);
        expect(
          visibleNumber(tester, target, spec.reeled),
          spec.frameAt(0).displayedValue(target),
          reason: '$value started before its delay elapsed',
        );

        // Half a run past its slot, not half a run past zero: the delay
        // is the figure's offset on the timeline, not a dead zone.
        if (!spec.isInstant) {
          captureRevealClock.value = offset + total ~/ 2;
          await tester.pump();
          final frame = spec.frameAt(0.5);
          // A reel sits BETWEEN cells mid-roll, so it is read as its own
          // fractional index rather than as a whole number.
          if (spec.reeled) {
            expect(slotProbe(tester, 0), closeTo(frame.progress * target, 1e-6));
          } else {
            expect(
              visibleNumber(tester, target, false),
              frame.displayedValue(target),
            );
          }
        }

        captureRevealClock.value = offset + total;
        await tester.pump();
        expect(visibleNumber(tester, target, spec.reeled), target);
        if (!spec.isInstant) {
          expect(signature(tester, target), isNot(beforeSlot));
        }
      });
    }
  });

  group('no value overshoots, and reaches its figure exactly once', () {
    for (final value in CountUpStyle.values) {
      test('$value', () {
        final spec = countUpSpec(value);
        var previousProgress = -1.0;
        var previousSweep = -1.0;
        var previousShown = -1;
        var landed = false;

        for (var i = 0; i <= steps; i++) {
          final t = i / steps;
          final frame = spec.frameAt(t);
          final at = 'at t=$t';

          // The figure never passes its value, and never walks back.
          expect(frame.progress, inInclusiveRange(-epsilon, 1 + epsilon),
              reason: at);
          expect(frame.progress, greaterThanOrEqualTo(previousProgress),
              reason: '$at the figure went backwards');
          previousProgress = frame.progress;

          // The arc sweeps one way only, and stays inside its range.
          expect(frame.arcSweep, inInclusiveRange(-epsilon, 1 + epsilon),
              reason: at);
          expect(frame.arcSweep, greaterThanOrEqualTo(previousSweep),
              reason: '$at the arc swept backwards');
          previousSweep = frame.arcSweep;
          expect(frame.arcOpacity, inInclusiveRange(-epsilon, 1 + epsilon),
              reason: at);

          // The number is reached once: never past the target, and never
          // off it again once it lands.
          final shown = frame.displayedValue(target);
          expect(shown, lessThanOrEqualTo(target), reason: at);
          expect(shown, greaterThanOrEqualTo(previousShown), reason: at);
          if (landed) {
            expect(shown, target, reason: '$at the figure left its target');
          }
          if (shown == target) landed = true;
          previousShown = shown;
        }

        // Whatever it did on the way, it ends settled: on the figure,
        // with no decoration left over.
        final end = spec.frameAt(1);
        expect(end.progress, closeTo(1, epsilon));
        expect(end.displayedValue(target), target);
        expect(end.arcOpacity, closeTo(0, epsilon));
      });
    }
  });

  group('every value that animates is processable', () {
    for (final value in CountUpStyle.values) {
      test('$value', () {
        final spec = countUpSpec(value);
        final total = spec.totalFor(CelebrationTimings.countUpDuration);

        if (spec.isInstant) {
          expect(total, Duration.zero);
          return;
        }

        expect(
          total,
          greaterThanOrEqualTo(totalFloor),
          reason: '$value runs $total — too short to leave a readable '
              'tail once the figure has landed',
        );
        expect(
          arrivalOf(spec),
          greaterThanOrEqualTo(arrivalFloor),
          reason: '$value resolves in ${arrivalOf(spec)} of visible '
              'change — the figure is over before the eye reaches it',
        );
      });
    }

    test('instant is the only value exempt from the floors', () {
      final exempt = [
        for (final value in CountUpStyle.values)
          if (countUpSpec(value).isInstant) value,
      ];
      expect(exempt, [CountUpStyle.instant]);
    });
  });

  group('the lead-in fits inside the intro it follows', () {
    // An intro owns the stage until it is done, so a count-up never
    // starts before the card has settled. What still matters is that a
    // value's lead-in is dead time the viewer is paying for AFTER an
    // intro they already watched — so cap it against the shortest intro
    // rather than against a hand-off that no longer exists.
    final flipRemaining = kFlipCountIntro.total;

    for (final value in CountUpStyle.values) {
      test('$value', () {
        final spec = countUpSpec(value);
        if (spec.isInstant) return;

        final leadIn = leadInOf(spec);
        expect(
          leadIn,
          lessThan(flipRemaining),
          reason: '$value waits $leadIn before the figure moves, past the '
              'flip it is supposed to start inside',
        );

        // Every authored value holds a beat first. `odometer` does not,
        // and must not: it is the parse fallback, so a hold there would
        // change what every unbranded build already ships.
        if (value != CountUpStyle.odometer) {
          expect(
            leadIn,
            greaterThanOrEqualTo(leadInFloor),
            reason: '$value starts counting the instant it mounts',
          );
        }
      });
    }
  });

  group('only the values that declare a device render it', () {
    test('the declarations', () {
      expect(countUpSpec(CountUpStyle.odometer).reeled, isTrue);
      expect(countUpSpec(CountUpStyle.ticker).reeled, isFalse);
      expect(countUpSpec(CountUpStyle.sweepArc).reeled, isFalse);
      expect(countUpSpec(CountUpStyle.instant).reeled, isFalse);

      expect(countUpSpec(CountUpStyle.sweepArc).hasArc, isTrue);
      for (final value in CountUpStyle.values) {
        if (value == CountUpStyle.sweepArc) continue;
        expect(countUpSpec(value).hasArc, isFalse);
      }
    });

    for (final value in CountUpStyle.values) {
      testWidgets('$value', (tester) async {
        phoneSized(tester);
        pin(value);
        final spec = countUpSpec(value);
        await tester.pumpWidget(host());
        await tester.pump(const Duration(milliseconds: 300));

        final arcs = find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is CountUpArcPainter,
        );
        expect(arcs, spec.hasArc ? findsOneWidget : findsNothing);

        // A reel is a strip of every integer the position passes
        // through; a plain cell is one glyph. Exactly one value pays for
        // the strip.
        final glyphs = find.descendant(
          of: find.byKey(CountUpFigure.slotKey(0)),
          matching: find.byType(Text),
        );
        expect(
          glyphs.evaluate().length,
          spec.reeled ? greaterThan(1) : 1,
          reason: '$value renders the wrong slot kind',
        );
      });
    }
  });

  test('the switch is wired to the right spec', () {
    for (final value in CountUpStyle.values) {
      expect(countUpSpec(value).value, value, reason: 'the switch is crossed');
    }
  });

  test('no count-up authors a bounce, elastic, or anticipation curve', () {
    final dir = Directory('lib/shared/widgets/animation/count_up');
    expect(dir.existsSync(), isTrue, reason: 'the count-up module moved');

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

    final files = [
      ...dir.listSync().whereType<File>(),
      File('lib/shared/widgets/animation/count_up_text.dart'),
    ];
    expect(files.length, greaterThan(1));
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

  group('the flipCount hand-off survives every count-up value', () {
    Widget card(PostClassController controller) {
      return DefaultAssetBundle(
        bundle: StubAssetBundle(),
        child: MaterialApp(
          home: PostClassScaffold(
            controller: controller,
            body: StreakBody(stats: mockStreakStats, controller: controller),
            ctaLabel: 'Continue',
            onCtaPressed: () {},
            onClose: () {},
          ),
        ),
      );
    }

    for (final value in CountUpStyle.values) {
      testWidgets('$value', (tester) async {
        phoneSized(tester);
        pin(value);
        FormatStore.instance.set(
          CombatDenSlots.celebrationIntro,
          CelebrationIntro.flipCount.name,
        );
        final controller = PostClassController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(card(controller));

        // One frame past the intro: the card has settled and the
        // count-up is mounted, and the hero has left. The intro owns
        // the stage until it is done — no count-up value may start
        // before that, and none may delay it afterwards.
        await tester.pump(
          kFlipCountIntro.total + const Duration(milliseconds: 16),
        );
        expect(find.byType(CountUpText), findsOneWidget);
        expect(
          find.byKey(CelebrationIntroFigure.heroKey),
          findsNothing,
          reason: 'the count-up no longer starts mid-flip',
        );

        await tester.pump(kFlipCountIntro.total);
        await tester.pump(const Duration(seconds: 4));

        expect(controller.isAnimating, isFalse);
        expect(find.byType(CountUpText), findsOneWidget);
        expect(labelled('${mockStreakStats.weekCount}'), findsOneWidget);
        expect(
          visibleNumber(
            tester,
            mockStreakStats.weekCount,
            countUpSpec(value).reeled,
          ),
          mockStreakStats.weekCount,
        );
      });
    }
  });
}
