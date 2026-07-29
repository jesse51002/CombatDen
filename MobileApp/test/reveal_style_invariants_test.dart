import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/formats/format_catalog.dart';
import 'package:mobile_app/core/formats/format_store.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/core/formats/motion_spec.dart';
import 'package:mobile_app/core/formats/theme_motion.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_body.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_day_badge.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_week_strip.dart';
import 'package:mobile_app/shared/widgets/animation/capture_reveal_clock.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_fade_up.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_figure.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_frame.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_stage.dart';
import 'package:mobile_app/shared/widgets/animation/scale_reveal.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// The functional-equivalence gate for `reveal_style`.
///
/// A motion format may change TIMING AND ENTRANCE ONLY. It may not
/// change which elements exist, what they are fed, where they end up, or
/// the app's motion law. This asserts all of it mechanically, for every
/// value:
///
/// * **Same element set.** Every value is driven to its settled state
///   and the rendered card compared against one contract. A reveal may
///   delay an element; it may never delete one.
/// * **Same landing.** Every element ends fully settled — no residual
///   opacity, transform, or clip — and lands on exactly the pixels the
///   shipped `fadeUp` lands on, which are exactly the pixels an
///   un-revealed element occupies.
/// * **Same order.** The stagger a call site authored with `delay:` is
///   untouched; a value's lead-in shifts the whole cascade, it never
///   reshuffles it.
/// * **Same motion law.** No value overshoots: sampled numerically off
///   each value's own frame function for range AND monotonicity (a
///   bounce is a reversal, so monotonicity catches what a range check
///   cannot), and backed by a source scan so an overshoot cannot
///   re-enter through a curve the frame model does not carry.
/// * **Legible.** Every value's run clears [kRevealLegibilityFloor] and
///   stays inside the app's element ceiling, so no value is over before
///   it is seen. There is no "no entrance" value at all.
///
/// Pumped at real phone size, because a card that only overflows once a
/// real body's height is in it would otherwise pass unnoticed.
void main() {
  const target = Key('reveal-target');
  const second = Key('reveal-second');
  const shipped = CelebrationTimings.revealDuration;

  /// The two knobs the shipped call sites actually bring, plus the
  /// `offset: 0` case (the wins trophy, the rewards carousel).
  const geometries = <RevealGeometry>[
    RevealGeometry(translate: 12),
    RevealGeometry(translate: 0),
    RevealGeometry(startScale: 0.5),
  ];

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
  void pin(RevealStyle style) {
    FormatStore.instance.set(CombatDenSlots.revealStyle, style.name);
  }

  Widget harness(Widget child) => DefaultAssetBundle(
    bundle: StubAssetBundle(),
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  Widget box({Key key = target}) =>
      SizedBox(key: key, width: 120, height: 40);

  RevealFigure figureFor(WidgetTester tester, Key key) =>
      tester.widget<RevealFigure>(
        find
            .ancestor(of: find.byKey(key), matching: find.byType(RevealFigure))
            .first,
      );

  /// Run ONE element's entrance out: the lead-in timer, then the run.
  Future<void> playOne(
    WidgetTester tester,
    RevealSpec spec, {
    Duration requested = shipped,
  }) async {
    await tester.pump(spec.leadIn);
    await tester.pump(
      spec.runFor(requested) + const Duration(milliseconds: 20),
    );
  }

  /// Run the whole streak card out: its `celebration_intro`, then the
  /// count-up, then the cascade of reveals underneath it.
  Future<void> playOutCard(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
  }

  Widget card({PostClassController? controller}) => DefaultAssetBundle(
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

  /// Every string the card renders, sorted — taken from the tree, not
  /// from a hand-written list of the elements someone remembered.
  List<String> cardTexts(WidgetTester tester) =>
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(StreakBody),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .toList()
        ..sort();

  /// Where every one of those strings sits, in tree order.
  List<Rect> cardTextRects(WidgetTester tester) => [
    for (final element
        in find
            .descendant(
              of: find.byType(StreakBody),
              matching: find.byType(Text),
            )
            .evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ];

  /// The settled streak card, derived from the mock rather than copied
  /// out of it, so a data change moves the contract with it.
  final settledContract = <String>[
    for (var i = 0; i <= mockStreakStats.weekCount; i++) '$i',
    'week streak',
    mockStreakStats.subtitle,
    ...mockStreakStats.weekDays.map((d) => d.label),
  ]..sort();

  void expectSettledCard(WidgetTester tester) {
    expect(cardTexts(tester), settledContract);
    expect(find.byType(CountUpText), findsOneWidget);
    expect(find.byType(StreakWeekStrip), findsOneWidget);
    expect(
      find.byType(StreakDayBadge),
      findsNWidgets(mockStreakStats.weekDays.length),
    );
  }

  /// No element is left mid-entrance: no residual opacity, transform, or
  /// clip anywhere in the tree.
  void expectEveryFigureSettled(WidgetTester tester, RevealStyle style) {
    final figures = tester.widgetList<RevealFigure>(
      find.byType(RevealFigure),
    );
    expect(figures, isNotEmpty, reason: '$style rendered no reveal at all');
    for (final figure in figures) {
      expect(
        figure.frame.isSettled,
        isTrue,
        reason:
            '$style left an element at opacity ${figure.frame.opacity}, '
            'rise ${figure.frame.rise}, slide ${figure.frame.slide}, '
            'scale ${figure.frame.scale}, clip ${figure.frame.clip}',
      );
    }
  }

  void expectRectsClose(List<Rect> actual, List<Rect> expected, String at) {
    expect(actual.length, expected.length, reason: at);
    for (var i = 0; i < actual.length; i++) {
      expect(actual[i].left, closeTo(expected[i].left, 0.01), reason: at);
      expect(actual[i].top, closeTo(expected[i].top, 0.01), reason: at);
      expect(actual[i].width, closeTo(expected[i].width, 0.01), reason: at);
      expect(actual[i].height, closeTo(expected[i].height, 0.01), reason: at);
    }
  }

  group('every value settles into the same element set', () {
    for (final style in RevealStyle.values) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(style);
        await tester.pumpWidget(card());
        await playOutCard(tester);

        expectSettledCard(tester);
        expectEveryFigureSettled(tester, style);
      });
    }
  });

  group('every value lands on the pixels the shipped value lands on', () {
    late List<Rect> reference;

    testWidgets('fadeUp (the reference)', (tester) async {
      phoneSized(tester);
      pin(RevealStyle.fadeUp);
      await tester.pumpWidget(card());
      await playOutCard(tester);
      reference = cardTextRects(tester);
      expect(reference, isNotEmpty);
    });

    for (final style in RevealStyle.values) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(RevealStyle.fadeUp);
        await tester.pumpWidget(card());
        await playOutCard(tester);
        final fadeUpRects = cardTextRects(tester);

        pin(style);
        await tester.pumpWidget(card());
        await playOutCard(tester);

        expectRectsClose(cardTextRects(tester), fadeUpRects, '$style');
        expectEveryFigureSettled(tester, style);
      });
    }
  });

  group('a revealed element settles where an un-revealed one sits', () {
    for (final style in RevealStyle.values) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        final spec = revealSpec(style);

        await tester.pumpWidget(harness(box()));
        final bare = tester.getRect(find.byKey(target));

        pin(style);
        await tester.pumpWidget(harness(StaggeredReveal(child: box())));
        await playOne(tester, spec);
        expectRectsClose(
          [tester.getRect(find.byKey(target))],
          [bare],
          '$style / StaggeredReveal',
        );
        expect(figureFor(tester, target).frame.isSettled, isTrue);

        await tester.pumpWidget(harness(ScaleReveal(child: box())));
        await playOne(tester, spec);
        expectRectsClose(
          [tester.getRect(find.byKey(target))],
          [bare],
          '$style / ScaleReveal',
        );
        expect(figureFor(tester, target).frame.isSettled, isTrue);
      });
    }
  });

  group('the call site owns the order, the value owns only the entrance', () {
    for (final style in RevealStyle.values) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(style);
        final spec = revealSpec(style);

        await tester.pumpWidget(
          harness(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StaggeredReveal(child: box()),
                StaggeredReveal(
                  delay: const Duration(milliseconds: 800),
                  child: box(key: second),
                ),
              ],
            ),
          ),
        );

        // The first element's whole entrance, lead-in included, still
        // finishes well inside the second's 800ms delay: a value can
        // shift a cascade, it cannot reorder one.
        await playOne(tester, spec);
        expect(
          figureFor(tester, target).frame.isSettled,
          isTrue,
          reason: '$style did not finish the undelayed element first',
        );
        expect(
          figureFor(tester, second).frame.isSettled,
          isFalse,
          reason: '$style let a delayed element arrive out of order',
        );

        // And the delayed one still lands. Two pumps: the first fires
        // its delay timer, the second gives its controller a tick.
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(
          figureFor(tester, second).frame.isSettled,
          isTrue,
          reason: '$style never finished the delayed element',
        );
      });
    }
  });

  group('the capture clock drives every value deterministically', () {
    for (final style in RevealStyle.values) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(style);
        final spec = revealSpec(style);

        // The harness sets the clock before the tree mounts.
        captureRevealClock.value = Duration.zero;
        await tester.pumpWidget(harness(StaggeredReveal(child: box())));

        expect(
          figureFor(tester, target).frame.isSettled,
          isFalse,
          reason: '$style arrives already settled; that is not an entrance',
        );

        // Held at one instant, the frame does not move on its own — the
        // clip's speed is the harness's to set, not the widget's.
        captureRevealClock.value =
            spec.leadIn + spec.runFor(shipped) ~/ 2;
        await tester.pump();
        final held = figureFor(tester, target).frame;
        await tester.pump(const Duration(seconds: 1));
        final stillHeld = figureFor(tester, target).frame;
        expect(stillHeld.opacity, held.opacity);
        expect(stillHeld.rise, held.rise);
        expect(stillHeld.slide, held.slide);
        expect(stillHeld.scale, held.scale);
        expect(stillHeld.clip, held.clip);
        expect(
          held.isSettled,
          isFalse,
          reason: '$style is already over halfway through its own run',
        );

        // Winding the clock past the end settles it.
        captureRevealClock.value =
            spec.totalFor(shipped) + const Duration(seconds: 5);
        await tester.pump();
        expect(figureFor(tester, target).frame.isSettled, isTrue);
      });
    }
  });

  group('no value overshoots its settled state', () {
    for (final style in RevealStyle.values) {
      test('$style', () {
        final spec = revealSpec(style);
        const steps = 400;
        const epsilon = 1e-9;

        for (final geometry in geometries) {
          final start = spec.frameAt(0, geometry);
          expect(
            start.isSettled,
            isFalse,
            reason: '$style does not animate in at all; every value is '
                'an entrance',
          );

          var previous = start;
          for (var i = 0; i <= steps; i++) {
            final t = i / steps;
            final f = spec.frameAt(t, geometry);
            final at = '$style at t=$t';

            // Inside range: nothing passes its settled value.
            expect(f.opacity, inInclusiveRange(-epsilon, 1 + epsilon),
                reason: at);
            expect(f.scale, inInclusiveRange(-epsilon, 1 + epsilon),
                reason: at);
            expect(f.clip, inInclusiveRange(-epsilon, 1 + epsilon),
                reason: at);
            // A displacement never passes its landing and comes back.
            expect(f.rise, greaterThanOrEqualTo(-epsilon), reason: at);
            expect(f.slide, greaterThanOrEqualTo(-epsilon), reason: at);
            // Nor does it start further out than it began.
            expect(f.rise, lessThanOrEqualTo(start.rise + epsilon),
                reason: at);
            expect(f.slide, lessThanOrEqualTo(start.slide + epsilon),
                reason: at);

            // Monotonic toward settled. A bounce, an elastic, or an
            // anticipation curve is a REVERSAL, which a range check
            // alone would wave through.
            expect(f.opacity, greaterThanOrEqualTo(previous.opacity - epsilon),
                reason: at);
            expect(f.scale, greaterThanOrEqualTo(previous.scale - epsilon),
                reason: at);
            expect(f.clip, greaterThanOrEqualTo(previous.clip - epsilon),
                reason: at);
            expect(f.rise, lessThanOrEqualTo(previous.rise + epsilon),
                reason: at);
            expect(f.slide, lessThanOrEqualTo(previous.slide + epsilon),
                reason: at);
            previous = f;
          }

          final end = spec.frameAt(1, geometry);
          expect(end.opacity, closeTo(1, epsilon), reason: '$style');
          expect(end.scale, closeTo(1, epsilon), reason: '$style');
          expect(end.clip, closeTo(1, epsilon), reason: '$style');
          expect(end.rise, closeTo(0, epsilon), reason: '$style');
          expect(end.slide, closeTo(0, epsilon), reason: '$style');
          expect(
            end.isSettled,
            isTrue,
            reason: '$style never fully arrives for $geometry',
          );
        }
      });
    }
  });

  group('every value is long enough to be read', () {
    for (final style in RevealStyle.values) {
      test('$style', () {
        final spec = revealSpec(style);
        expect(
          spec.minDuration,
          greaterThanOrEqualTo(kRevealLegibilityFloor),
          reason: '$style is over before a viewer can process it',
        );
        expect(
          spec.minDuration,
          lessThanOrEqualTo(MotionSpec.elementDurationCeiling),
          reason: "$style exceeds the app's per-element motion ceiling",
        );
        expect(spec.leadIn, greaterThanOrEqualTo(Duration.zero));
        // A call site asking for something too quick to see is raised to
        // the floor; one asking for longer keeps its own length.
        expect(
          spec.runFor(const Duration(milliseconds: 80)),
          spec.minDuration,
        );
        expect(
          spec.runFor(const Duration(milliseconds: 720)),
          const Duration(milliseconds: 720),
        );
        expect(spec.value, style, reason: 'the switch is mis-wired');
      });
    }
  });

  group('the shipped entrance is reproduced verbatim', () {
    test('fadeUp is unpadded and runs for the shipped duration', () {
      expect(kFadeUpReveal.leadIn, Duration.zero);
      expect(kFadeUpReveal.minDuration, CelebrationTimings.revealDuration);
      expect(kFadeUpReveal.runFor(shipped), shipped);
      expect(kFadeUpReveal.totalFor(shipped), shipped);
      expect(RevealStyle.values.first, RevealStyle.fadeUp);
      expect(revealSpec(RevealStyle.fadeUp), same(kFadeUpReveal));
    });

    test('fadeUp is StaggeredReveal and ScaleReveal, frame for frame', () {
      const steps = 200;
      const epsilon = 1e-12;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final v = Curves.easeOutQuart.transform(t);

        // What `StaggeredReveal` painted before the enum existed:
        // Opacity(v) over Transform.translate(0, offset * (1 - v)).
        final staggered = kFadeUpReveal.frameAt(
          t,
          const RevealGeometry(translate: 12),
        );
        expect(staggered.opacity, closeTo(v, epsilon), reason: 't=$t');
        expect(staggered.rise, closeTo(12 * (1 - v), epsilon), reason: 't=$t');
        expect(staggered.slide, 0);
        expect(staggered.scale, 1);
        expect(staggered.clip, 1);

        // And what `ScaleReveal` painted: Opacity(v) over
        // Transform.scale(startScale + (1 - startScale) * v).
        final scaled = kFadeUpReveal.frameAt(
          t,
          const RevealGeometry(startScale: 0.5),
        );
        expect(scaled.opacity, closeTo(v, epsilon), reason: 't=$t');
        expect(scaled.scale, closeTo(0.5 + 0.5 * v, epsilon), reason: 't=$t');
        expect(scaled.rise, 0);
        expect(scaled.slide, 0);
        expect(scaled.clip, 1);
      }
    });

    test('a call site that asked not to move is never moved', () {
      for (final style in RevealStyle.values) {
        final spec = revealSpec(style);
        for (var i = 0; i <= 100; i++) {
          final f = spec.frameAt(i / 100, const RevealGeometry(translate: 0));
          expect(f.rise, 0, reason: '$style displaced an `offset: 0` element');
          expect(f.slide, 0, reason: '$style displaced an `offset: 0` element');
        }
      }
    });
  });

  test('no reveal authors a bounce, elastic, or anticipation curve', () {
    final dir = Directory('lib/shared/widgets/animation/reveal');
    expect(dir.existsSync(), isTrue, reason: 'the reveal module moved');

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
      File('lib/shared/widgets/animation/staggered_reveal.dart'),
      File('lib/shared/widgets/animation/scale_reveal.dart'),
    ];
    expect(files.length, greaterThan(2));
    for (final file in files) {
      expect(file.existsSync(), isTrue, reason: '${file.path} moved');
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

  group('an unrecognised slot value degrades to the shipped entrance', () {
    // Load-bearing rather than incidental: `none` was a real value and a
    // theme may still be sending it. The parser's fallback is what makes
    // that safe, so it is pinned here — if someone changes the fallback
    // or the parser, this fails loudly instead of a screen going blank.
    for (final wire in ['none', 'None', 'not-a-style', '', '   ']) {
      test('"$wire"', () {
        FormatStore.instance.set(CombatDenSlots.revealStyle, wire);
        expect(ThemeMotion.reveal(), RevealStyle.fadeUp);
        expect(RevealStyle.fromWire(wire), RevealStyle.fadeUp);
      });
    }

    test('there is no "no entrance" value', () {
      expect(
        RevealStyle.values.map((v) => v.name),
        isNot(contains('none')),
        reason: 'every reveal_style value must actually animate in',
      );
    });
  });

  test('the catalog offers reveal_style as implemented', () {
    final entry = kMotionFormats.firstWhere(
      (e) => e.slot == CombatDenSlots.revealStyle,
    );
    expect(entry.implemented, isTrue);
    expect(
      entry.values,
      RevealStyle.values.map((v) => v.name).toList(),
    );
    expect(entry.shipped, RevealStyle.fadeUp.name);
  });

  group('the card is never stranded mid-entrance', () {
    for (final style in RevealStyle.values) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(style);
        final controller = PostClassController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(card(controller: controller));
        await playOutCard(tester);

        // A reveal that never completes is a CTA that never appears.
        expect(controller.isAnimating, isFalse);
        expect(find.byType(AppPrimaryButton), findsOneWidget);
        expectSettledCard(tester);
        expectEveryFigureSettled(tester, style);
      });
    }
  });
}
