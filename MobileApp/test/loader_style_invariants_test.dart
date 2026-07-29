import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/formats/format_store.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_dots.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_figure.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';
import 'package:mobile_app/shared/widgets/animation/loading_dots.dart';

/// The functional-equivalence gate for `loader_style`.
///
/// A motion format may change TIMING AND ENTRANCE ONLY. It may not
/// change which elements exist, what the surface is fed, or the app's
/// motion law. For a loader that resolves into five mechanical claims,
/// asserted here for EVERY value:
///
/// * **Same element set, same footprint.** One waiting indicator, no
///   text, filling the identical box. A format picks the figure; it does
///   not get to take more of the screen it is waiting on.
/// * **It actually moves.** The frame at t=0 differs from the frame half
///   a cycle later, at the widget, not just in the model.
/// * **It never settles.** Twenty cycles in it is still running, and the
///   loop closes on itself so there is no cut back to the start.
/// * **A pinned phase is honoured exactly.** Given `value`, the widget
///   renders that instant and no ticker runs — this is what lets the
///   capture harness export a clip at true speed.
/// * **Same motion law.** No mark passes its settled size, its track, or
///   its rest line: sampled numerically off each value's own frame
///   function, backed by a source scan so an overshoot cannot re-enter
///   through a curve the frame model does not carry.
///
/// Plus one perceptual floor: a cycle has to be readable AS a cycle.
void main() {
  tearDown(FormatStore.instance.reset);

  /// Pin the tenant slot, exactly as the dev picker does at runtime.
  void pin(LoaderStyle style) =>
      FormatStore.instance.set(CombatDenSlots.loaderStyle, style.name);

  Widget loader({double? value}) => withStubAssets(
    MaterialApp(
      home: Scaffold(body: Center(child: LoadingDots(value: value))),
    ),
  );

  LoaderFigure figure(WidgetTester tester) =>
      tester.widget<LoaderFigure>(find.byType(LoaderFigure));

  /// Every number a frame carries, as one comparable string. The
  /// comparison is over what the widget is actually rendering, not over
  /// a hand-written list of the channels someone remembered.
  String describe(LoaderFrame frame) => frame.marks
      .map(
        (m) => [
          m.x,
          m.lift,
          m.scale,
          m.opacity,
        ].map((v) => v.toStringAsFixed(6)).join(','),
      )
      .join(' | ');

  // The box every value fills: the shipped dots' own footprint.
  const shippedBox = Size(3 * 24 + 2 * 16, 24 + 28);

  group('every value renders one waiting indicator, in the same box', () {
    for (final style in LoaderStyle.values) {
      testWidgets('$style', (tester) async {
        pin(style);
        await tester.pumpWidget(loader());

        expect(find.byType(LoaderFigure), findsOneWidget);
        expect(
          figure(tester).spec.value,
          style,
          reason: 'the switch is mis-wired',
        );
        expect(
          tester.getSize(find.byType(LoadingDots)),
          shippedBox,
          reason: '$style resized the waiting state',
        );
        // A loader waits; it does not narrate. No value gets to add a
        // caption the shipped one never had.
        expect(
          find.descendant(
            of: find.byType(LoadingDots),
            matching: find.byType(Text),
          ),
          findsNothing,
        );
        expect(figure(tester).frame.marks.length, loaderSpec(style).markCount);
      });
    }
  });

  group('every value animates', () {
    for (final style in LoaderStyle.values) {
      testWidgets('$style', (tester) async {
        pin(style);
        await tester.pumpWidget(loader());
        final atStart = describe(figure(tester).frame);

        await tester.pump(loaderSpec(style).cycle ~/ 2);

        expect(
          describe(figure(tester).frame),
          isNot(atStart),
          reason: '$style is static: a loader that does not move is a '
              'frozen app, not a waiting state',
        );
      });
    }
  });

  group('every value keeps going and never settles', () {
    for (final style in LoaderStyle.values) {
      testWidgets('$style', (tester) async {
        pin(style);
        await tester.pumpWidget(loader());

        // Twenty cycles in, it is still on the clock.
        await tester.pump(loaderSpec(style).cycle * 20);
        expect(
          tester.binding.transientCallbackCount,
          greaterThan(0),
          reason: '$style stopped ticking',
        );

        final late20 = describe(figure(tester).frame);
        await tester.pump(loaderSpec(style).cycle ~/ 3);
        expect(
          describe(figure(tester).frame),
          isNot(late20),
          reason: '$style settled instead of repeating',
        );
      });
    }
  });

  group('an explicit value pins the phase and nothing self-animates', () {
    for (final style in LoaderStyle.values) {
      testWidgets('$style', (tester) async {
        pin(style);
        const phase = 0.37;
        await tester.pumpWidget(loader(value: phase));

        final expected = describe(loaderSpec(style).frameAt(phase));
        expect(describe(figure(tester).frame), expected);
        expect(
          tester.binding.transientCallbackCount,
          0,
          reason: '$style ran a ticker under a pinned phase',
        );

        await tester.pump(const Duration(seconds: 3));
        expect(
          describe(figure(tester).frame),
          expected,
          reason: '$style drifted off the phase the harness pinned',
        );

        // A different phase is a different instant — the pin is read,
        // not merely tolerated.
        await tester.pumpWidget(loader(value: 0.81));
        expect(
          describe(figure(tester).frame),
          describe(loaderSpec(style).frameAt(0.81)),
        );
      });
    }
  });

  group('no value overshoots', () {
    for (final style in LoaderStyle.values) {
      test('$style', () {
        final spec = loaderSpec(style);
        const steps = 400;
        const epsilon = 1e-9;

        for (var i = 0; i <= steps; i++) {
          final t = i / steps;
          final frame = spec.frameAt(t);
          final at = '$style at t=$t';

          expect(frame.marks.length, spec.markCount, reason: at);
          for (final mark in frame.marks) {
            // Scale never passes the mark's settled size.
            expect(mark.scale, lessThanOrEqualTo(1 + epsilon), reason: at);
            expect(mark.scale, greaterThanOrEqualTo(-epsilon), reason: at);
            // A mark never dips below its rest line and comes back.
            expect(mark.lift, greaterThanOrEqualTo(-epsilon), reason: at);
            expect(mark.lift, lessThanOrEqualTo(1 + epsilon), reason: at);
            // Nothing travels outside the box it shares.
            expect(
              mark.x,
              inInclusiveRange(-1 - epsilon, 1 + epsilon),
              reason: at,
            );
            expect(
              mark.opacity,
              inInclusiveRange(-epsilon, 1 + epsilon),
              reason: at,
            );
          }
        }
      });
    }
  });

  group('every cycle closes on itself', () {
    for (final style in LoaderStyle.values) {
      test('$style', () {
        final spec = loaderSpec(style);
        expect(
          describe(spec.frameAt(1)),
          describe(spec.frameAt(0)),
          reason: '$style cuts back to its start once a cycle instead of '
              'running continuously',
        );
      });
    }
  });

  group('every value disposes cleanly', () {
    for (final style in LoaderStyle.values) {
      testWidgets('$style', (tester) async {
        pin(style);
        await tester.pumpWidget(loader());
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.binding.transientCallbackCount, greaterThan(0));

        await tester.pumpWidget(const SizedBox.shrink());

        expect(
          tester.binding.transientCallbackCount,
          0,
          reason: '$style leaked its controller: an indefinite animation '
              'that outlives its widget runs forever',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the picker swaps the loader in place, without a leak', (
    tester,
  ) async {
    pin(LoaderStyle.dots);
    await tester.pumpWidget(loader());
    expect(figure(tester).spec.value, LoaderStyle.dots);

    for (final style in LoaderStyle.values) {
      pin(style);
      await tester.pump();
      expect(find.byType(LoaderFigure), findsOneWidget);
      expect(figure(tester).spec.value, style);
      // One swap, one live ticker — the outgoing value's controller went
      // with it.
      expect(tester.binding.transientCallbackCount, 1, reason: '$style');
    }
  });

  test('no value strobes: every cycle is long enough to read', () {
    // A cycle has to be perceivable AS a cycle. Under about eight tenths
    // of a second a repeat registers as a flicker or a fault rather than
    // as work in progress, and a frantic loader makes a wait feel worse
    // than a calm one. The floor sits below the shipped dots' 1100ms on
    // purpose, so it constrains new values instead of merely restating
    // today's. Values may differ in tempo above it — they may not be
    // illegible.
    const floor = Duration(milliseconds: 800);
    for (final style in LoaderStyle.values) {
      expect(
        loaderSpec(style).cycle,
        greaterThanOrEqualTo(floor),
        reason: '$style strobes',
      );
    }
  });

  test('no loader authors a bounce, elastic, or anticipation curve', () {
    final dir = Directory('lib/shared/widgets/animation/loader');
    expect(dir.existsSync(), isTrue, reason: 'the loader module moved');

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
      File('lib/shared/widgets/animation/loading_dots.dart'),
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

  group('the shipped value is untouched', () {
    test('dots is the fallback and keeps its own numbers', () {
      expect(LoaderStyle.values.first, LoaderStyle.dots);
      expect(LoaderStyle.fromWire(null), LoaderStyle.dots);
      expect(LoaderStyle.fromWire('not-a-value'), LoaderStyle.dots);
      expect(kDotsLoader.cycle, const Duration(milliseconds: 1100));
      expect(kDotsLoader.markCount, 3);
    });

    test('dots reproduces the shipped travelling wave exactly', () {
      for (var i = 0; i <= 200; i++) {
        final t = i / 200;
        final marks = kDotsLoader.frameAt(t).marks;
        for (var d = 0; d < 3; d++) {
          final phase = (t + d / 3) % 1.0;
          expect(
            marks[d].lift,
            closeTo(math.max(0.0, math.sin(phase * 2 * math.pi)), 1e-12),
            reason: 'dot $d at t=$t',
          );
          expect(marks[d].x, closeTo(d - 1.0, 1e-12));
          expect(marks[d].scale, 1);
          expect(marks[d].opacity, 1);
        }
      }
    });

    testWidgets('dots lands its circles where the shipped loader did', (
      tester,
    ) async {
      pin(LoaderStyle.dots);
      await tester.pumpWidget(loader(value: 0));

      final dots = find.descendant(
        of: find.byType(LoaderFigure),
        matching: find.byType(DecoratedBox),
      );
      expect(dots, findsNWidgets(3));

      final origin = tester.getTopLeft(find.byType(LoaderFigure));
      // The shipped geometry: `left = i * (dotSize + spacing)`,
      // `bottom = wave * bounceHeight` on a 24/16/28 box.
      const step = 24.0 + 16.0;
      for (var d = 0; d < 3; d++) {
        final wave = math.max(0.0, math.sin(d / 3 * 2 * math.pi));
        final topLeft = tester.getTopLeft(dots.at(d)) - origin;
        expect(topLeft.dx, closeTo(d * step, 1e-6), reason: 'dot $d x');
        expect(
          topLeft.dy,
          closeTo(28 - wave * 28, 1e-6),
          reason: 'dot $d y',
        );
      }
    });
  });
}
