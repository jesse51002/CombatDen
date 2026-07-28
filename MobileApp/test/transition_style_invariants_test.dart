import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/formats/format_catalog.dart';
import 'package:mobile_app/core/formats/format_store.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:mobile_app/shared/themes/app_theme.dart';
import 'package:mobile_app/shared/themes/transitions/app_page_transitions.dart';
import 'package:mobile_app/shared/themes/transitions/card_stack_page_transitions_builder.dart';
import 'package:mobile_app/shared/themes/transitions/fade_page_transitions_builder.dart';
import 'package:mobile_app/shared/themes/transitions/instant_page_transitions_builder.dart';
import 'package:mobile_app/shared/themes/transitions/shared_axis_page_transitions_builder.dart';
import 'package:mobile_app/shared/themes/transitions/transition_motion.dart';

/// The functional-equivalence gate for `transition_style`.
///
/// A motion format may change TIMING AND ENTRANCE ONLY. For a page
/// transition that means it decides how a route animates and nothing
/// else, and this asserts all of it mechanically, for every value:
///
/// * **It completes.** Every value pushes and pops, settles, and leaves
///   nothing moving.
/// * **Same destination.** The screen you land on renders the same
///   element set whichever value is pinned — proved on a fixture with a
///   declared contract and again on a real screen.
/// * **Same navigation.** `pushNamed` still stacks, `pop` still
///   returns, `pushReplacementNamed` still replaces. The enum never
///   reaches the back stack.
/// * **Same motion law.** No value overshoots its landing, none starts
///   with a lead-in, and none reaches for a bounce or elastic curve.
/// * **`platformDefault` changes nothing.** Not "looks the same" —
///   frame-for-frame identical geometry and an identical widget chain
///   against the theme the app had before this enum was wired.
///
/// Pumped at real phone size, because a transition's travel is a
/// fraction of the screen and a 800x600 test surface would understate
/// every distance it moves.
void main() {
  tearDown(FormatStore.instance.reset);

  /// Pin the tenant slot, exactly as the dev picker does at runtime.
  void pin(TransitionStyle style) {
    FormatStore.instance.set(CombatDenSlots.transitionStyle, style.name);
  }

  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Rect screenRect(WidgetTester tester) =>
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

  /// The whole app under test: named routes, pushed by name, exactly as
  /// `core/app_routes.dart` declares them. Nothing here knows a
  /// transition exists — which is the point of wiring the enum into the
  /// theme instead of into the navigator.
  Widget app({
    required GlobalKey<NavigatorState> navigatorKey,
    ThemeData? theme,
    Key? appKey,
  }) {
    return DefaultAssetBundle(
      bundle: StubAssetBundle(),
      child: MaterialApp(
        key: appKey,
        navigatorKey: navigatorKey,
        theme: theme ?? AppTheme.forCanvas(),
        initialRoute: _kOriginRoute,
        routes: {
          _kOriginRoute: (_) => const _OriginFixture(),
          _kDetailRoute: (_) => const _DetailFixture(),
          _kReplacedRoute: (_) => const _ReplacedFixture(),
          _kPagerRoute: (_) => const _PagerFixture(),
          _kProfileRoute: (_) => const ProfileScreen(),
        },
      ),
    );
  }

  /// The theme the app carried BEFORE this enum was wired: identical in
  /// every other respect, with the framework's own page transitions.
  ThemeData beforeThisChange() =>
      AppTheme.forCanvas().copyWith(
        pageTransitionsTheme: const PageTransitionsTheme(),
      );

  /// Opacity actually applied to [key], accumulated through every
  /// fade in its ancestry. A value that settles a screen at anything
  /// other than 1 is a value that left the app dimmed.
  double appliedOpacity(WidgetTester tester, Key key) {
    var opacity = 1.0;
    for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(of: find.byKey(key), matching: find.byType(FadeTransition)),
    )) {
      opacity *= fade.opacity.value;
    }
    for (final layer in tester.widgetList<Opacity>(
      find.ancestor(of: find.byKey(key), matching: find.byType(Opacity)),
    )) {
      opacity *= layer.opacity;
    }
    return opacity;
  }

  /// Every widget type between [key] and the root, in order.
  List<String> ancestorChain(WidgetTester tester, Key key) => tester
      .widgetList(
        find.ancestor(
          of: find.byKey(key),
          matching: find.byWidgetPredicate((_) => true),
        ),
      )
      .map((widget) => widget.runtimeType.toString())
      .toList(growable: false);

  void expectSettled(WidgetTester tester, Key key, {required String reason}) {
    final rect = tester.getRect(find.byKey(key));
    final screen = screenRect(tester);
    expect(rect.left, closeTo(screen.left, _kEpsilon), reason: reason);
    expect(rect.top, closeTo(screen.top, _kEpsilon), reason: reason);
    expect(rect.width, closeTo(screen.width, _kEpsilon), reason: reason);
    expect(rect.height, closeTo(screen.height, _kEpsilon), reason: reason);
    expect(appliedOpacity(tester, key), closeTo(1, _kEpsilon), reason: reason);
  }

  /// Tap through to the detail route and stop on the transition's first
  /// frame. Two pumps, not one: the framework lays a freshly pushed
  /// route out offstage for a frame before it animates, so a single
  /// pump would sample a screen that is not on the stage yet. No time
  /// elapses across either, so this lands at t=0 of the transition.
  Future<void> pushDetail(WidgetTester tester) async {
    await tester.tap(find.text(_kPushLabel));
    await tester.pump();
    await tester.pump();
  }

  /// The strings the fixture's own area renders, sorted — the same
  /// comparison the celebration gate makes, over what is actually in
  /// the tree rather than over a list someone remembered.
  List<String> textsUnder(WidgetTester tester, Finder scope) =>
      tester
          .widgetList<Text>(
            find.descendant(of: scope, matching: find.byType(Text)),
          )
          .map((text) => text.data ?? '')
          .toList()
        ..sort();

  group('every value completes a push and a pop and settles', () {
    for (final style in TransitionStyle.values) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(style);
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(app(navigatorKey: nav));

        expectSettled(tester, _kOriginKey, reason: '$style origin at rest');
        expect(nav.currentState!.canPop(), isFalse);

        await tester.tap(find.text(_kPushLabel));
        await tester.pumpAndSettle();

        expect(find.byKey(_kDetailKey), findsOneWidget);
        expect(nav.currentState!.canPop(), isTrue, reason: 'push must stack');
        expectSettled(
          tester,
          _kDetailKey,
          reason: '$style left the destination un-settled',
        );

        await tester.tap(find.text(_kPopLabel));
        await tester.pumpAndSettle();

        expect(find.byKey(_kOriginKey), findsOneWidget);
        expect(find.byKey(_kDetailKey), findsNothing);
        expect(nav.currentState!.canPop(), isFalse);
        expectSettled(
          tester,
          _kOriginKey,
          reason: '$style left the origin un-settled after a pop',
        );
      });
    }
  });

  group('the destination renders the same element set for every value', () {
    for (final style in TransitionStyle.values) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(style);
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(app(navigatorKey: nav));

        await tester.tap(find.text(_kPushLabel));
        await tester.pumpAndSettle();

        expect(textsUnder(tester, find.byKey(_kDetailKey)), _kDetailContract);
      });
    }
  });

  testWidgets('a real screen arrives whole through every value', (
    tester,
  ) async {
    phoneSized(tester);
    List<String>? reference;

    for (final style in TransitionStyle.values) {
      pin(style);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        app(navigatorKey: nav, appKey: ValueKey('profile-${style.name}')),
      );

      await tester.tap(find.text(_kProfileLabel));
      // The screen's own celebration hero animates in on mount; run it
      // out so what is compared is the settled screen.
      await tester.pump(const Duration(milliseconds: 32));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(ProfileScreen), findsOneWidget, reason: '$style');
      final texts = textsUnder(tester, find.byType(ProfileScreen));
      expect(texts, isNotEmpty, reason: '$style rendered an empty screen');
      reference ??= texts;
      expect(
        texts,
        reference,
        reason: '$style changed what the screen renders',
      );
    }
  });

  group('the enum never reaches the back stack', () {
    for (final style in TransitionStyle.values) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(style);
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(app(navigatorKey: nav));

        // A replacement stays a replacement: the origin is gone and
        // there is nothing to pop back to.
        await tester.tap(find.text(_kReplaceLabel));
        await tester.pumpAndSettle();

        expect(find.byKey(_kReplacedKey), findsOneWidget);
        expect(find.byKey(_kOriginKey), findsNothing);
        expect(
          nav.currentState!.canPop(),
          isFalse,
          reason: '$style turned a replacement into a push',
        );
      });
    }
  });

  group('the screen keeps its own horizontal drag', () {
    // The home day pager, the class screen's swipe into post-class, and
    // the rewards carousel are all horizontal drags living INSIDE a
    // screen. A transition that left a transform or an IgnorePointer
    // behind would eat them, so this drags one for real.
    for (final style in TransitionStyle.values) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(style);
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(app(navigatorKey: nav));

        await tester.tap(find.text(_kPagerLabel));
        await tester.pumpAndSettle();
        expect(find.text(_kPagerPages.first), findsOneWidget);

        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        expect(
          find.text(_kPagerPages[1]),
          findsOneWidget,
          reason: '$style swallowed the screen\'s own drag',
        );
        expect(find.text(_kPagerPages.first), findsNothing);
      });
    }
  });

  group('no value overshoots its landing', () {
    for (final entry in _kEnvelopes.entries) {
      testWidgets('${entry.key}', (tester) async {
        phoneSized(tester);
        pin(entry.key);
        final envelope = entry.value;
        final screen = screenRect(tester);
        final duration = AppPageTransitions.builderFor(
          entry.key,
          TargetPlatform.android,
        ).transitionDuration;

        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(app(navigatorKey: nav));
        await pushDetail(tester);

        const steps = 60;
        for (var i = 0; i <= steps; i++) {
          final at = 'at step $i of ${entry.key}';
          final arriving = tester.getRect(find.byKey(_kDetailKey));

          // The arriving screen comes from its start offset and stops
          // dead on the screen: it never travels past its landing and
          // comes back, and never starts further out than declared.
          expect(
            arriving.left,
            inInclusiveRange(
              -_kEpsilon,
              envelope.fromX * screen.width + _kEpsilon,
            ),
            reason: at,
          );
          expect(
            arriving.top,
            inInclusiveRange(
              -_kEpsilon,
              envelope.fromY * screen.height + _kEpsilon,
            ),
            reason: at,
          );
          // Nothing scales up past full size on the way in.
          expect(
            arriving.width,
            lessThanOrEqualTo(screen.width + _kEpsilon),
            reason: at,
          );
          expect(
            arriving.height,
            lessThanOrEqualTo(screen.height + _kEpsilon),
            reason: at,
          );
          expect(
            appliedOpacity(tester, _kDetailKey),
            inInclusiveRange(-_kEpsilon, 1 + _kEpsilon),
            reason: at,
          );

          // The covered screen leaves the stage once the transition is
          // over; while it is still on it, it carries on in one
          // direction and recedes no further than declared.
          if (find.byKey(_kOriginKey).evaluate().isNotEmpty) {
            final leaving = tester.getRect(find.byKey(_kOriginKey));
            // Sliding moves its left edge out; receding about the
            // centre moves it in by half of what it gives up. It may
            // reach either bound and no further, in either direction.
            expect(
              leaving.left,
              inInclusiveRange(
                -envelope.leavingX * screen.width - _kEpsilon,
                (1 - envelope.leavingScale) / 2 * screen.width + _kEpsilon,
              ),
              reason: at,
            );
            expect(
              leaving.width,
              inInclusiveRange(
                envelope.leavingScale * screen.width - _kEpsilon,
                screen.width + _kEpsilon,
              ),
              reason: at,
            );
            expect(
              appliedOpacity(tester, _kOriginKey),
              inInclusiveRange(-_kEpsilon, 1 + _kEpsilon),
              reason: at,
            );
          }

          await tester.pump(duration ~/ steps);
        }

        await tester.pumpAndSettle();
        expectSettled(tester, _kDetailKey, reason: '${entry.key} settle');
      });
    }
  });

  group('no value leads in', () {
    for (final style in _kEnvelopes.keys) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(style);
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(app(navigatorKey: nav));
        await pushDetail(tester);

        final start = tester.getRect(find.byKey(_kDetailKey)).topLeft;
        final startOpacity = appliedOpacity(tester, _kDetailKey);

        // A transition answers a tap, so it moves on frame one. Delay
        // reads as input lag, never as drama.
        await tester.pump(const Duration(milliseconds: 16));

        final moved =
            (tester.getRect(find.byKey(_kDetailKey)).topLeft - start).distance;
        final faded =
            (appliedOpacity(tester, _kDetailKey) - startOpacity).abs();
        expect(
          moved + faded,
          greaterThan(_kEpsilon),
          reason: '$style holds still on frame one; a page transition '
              'may not lead in',
        );

        await tester.pumpAndSettle();
      });
    }
  });

  group('every authored value is long enough to be read', () {
    for (final style in _kAuthored) {
      test('$style', () {
        final builder = AppPageTransitions.builderFor(
          style,
          TargetPlatform.android,
        );
        expect(
          builder.transitionDuration,
          greaterThanOrEqualTo(TransitionMotion.legibilityFloor),
          reason: '$style is too short to read as a movement',
        );
        expect(
          builder.reverseTransitionDuration,
          greaterThanOrEqualTo(TransitionMotion.legibilityFloor),
          reason: '$style pops too fast to read as a movement',
        );
      });
    }
  });

  test('none is a cut, not a very fast animation', () {
    expect(
      AppPageTransitions.builderFor(
        TransitionStyle.none,
        TargetPlatform.android,
      ).transitionDuration,
      Duration.zero,
    );
    expect(
      AppPageTransitions.builderFor(
        TransitionStyle.none,
        TargetPlatform.android,
      ).reverseTransitionDuration,
      Duration.zero,
    );
  });

  testWidgets('none lands the destination on the very next frame', (
    tester,
  ) async {
    phoneSized(tester);
    pin(TransitionStyle.none);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(navigatorKey: nav));

    await pushDetail(tester);

    expectSettled(tester, _kDetailKey, reason: 'none must cut, not animate');
    // A completed route is opaque, so the screen it covered is off the
    // stage already. Anything still animating would keep it on.
    expect(
      find.byKey(_kOriginKey),
      findsNothing,
      reason: 'none still had a transition running one frame in',
    );
  });

  group('every authored value takes its whole duration', () {
    for (final style in _kAuthored) {
      testWidgets('$style', (tester) async {
        phoneSized(tester);
        pin(style);
        final duration = AppPageTransitions.builderFor(
          style,
          TargetPlatform.android,
        ).transitionDuration;

        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(app(navigatorKey: nav));
        await pushDetail(tester);
        await tester.pump(duration ~/ 2);

        // Half way in, the screen it covered is still on stage: the
        // route has not completed, so there is still motion to read.
        expect(
          find.byKey(_kOriginKey),
          findsOneWidget,
          reason: '$style was over before half its duration',
        );

        await tester.pumpAndSettle();
        expect(find.byKey(_kOriginKey), findsNothing);
      });
    }
  });

  group('platformDefault is a genuine no-op', () {
    test('it hands the route back to the framework, per platform', () {
      const stock = PageTransitionsTheme();
      for (final platform in TargetPlatform.values) {
        final expected =
            stock.builders[platform] ?? const ZoomPageTransitionsBuilder();
        expect(
          AppPageTransitions.builderFor(
            TransitionStyle.platformDefault,
            platform,
          ),
          same(expected),
          reason: 'platformDefault authored a transition on $platform',
        );
      }
    });

    test('every platform is registered, so no lookup falls through', () {
      final builders = AppPageTransitions.theme().builders;
      for (final platform in TargetPlatform.values) {
        expect(builders[platform], isNotNull, reason: '$platform');
      }
    });

    testWidgets('it animates frame-for-frame like the untouched theme', (
      tester,
    ) async {
      phoneSized(tester);
      pin(TransitionStyle.platformDefault);

      Future<List<Rect>> sample(ThemeData theme, String label) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          app(navigatorKey: nav, theme: theme, appKey: ValueKey(label)),
        );
        await pushDetail(tester);

        final rects = <Rect>[];
        for (var i = 0; i < 40; i++) {
          rects.add(tester.getRect(find.byKey(_kDetailKey)));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        return rects;
      }

      final before = await sample(beforeThisChange(), 'before');
      final after = await sample(AppTheme.forCanvas(), 'after');

      expect(after, before, reason: 'platformDefault changed the geometry');
    });

    testWidgets('it builds the same widget chain as the untouched theme', (
      tester,
    ) async {
      phoneSized(tester);
      pin(TransitionStyle.platformDefault);

      Future<List<String>> chainAt(ThemeData theme, String label) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          app(navigatorKey: nav, theme: theme, appKey: ValueKey(label)),
        );
        await pushDetail(tester);
        await tester.pump(const Duration(milliseconds: 100));
        final chain = ancestorChain(tester, _kDetailKey);
        await tester.pumpAndSettle();
        return chain;
      }

      final before = await chainAt(beforeThisChange(), 'before');
      final after = await chainAt(AppTheme.forCanvas(), 'after');

      expect(after, before, reason: 'platformDefault wrapped the route');
    });

    testWidgets('it runs for the framework\'s own duration', (tester) async {
      phoneSized(tester);
      pin(TransitionStyle.platformDefault);
      final stock = AppPageTransitions.stockBuilderFor(TargetPlatform.android);

      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(navigatorKey: nav));
      await pushDetail(tester);
      await tester.pump(stock.transitionDuration ~/ 2);
      expect(find.byKey(_kOriginKey), findsOneWidget);

      await tester.pump(stock.transitionDuration);
      await tester.pumpAndSettle();
      expect(find.byKey(_kOriginKey), findsNothing);
    });
  });

  test('every value resolves to its own builder', () {
    const platform = TargetPlatform.android;
    expect(
      AppPageTransitions.builderFor(TransitionStyle.fade, platform),
      isA<FadePageTransitionsBuilder>(),
    );
    expect(
      AppPageTransitions.builderFor(TransitionStyle.sharedAxis, platform),
      isA<SharedAxisPageTransitionsBuilder>(),
    );
    expect(
      AppPageTransitions.builderFor(TransitionStyle.cardStack, platform),
      isA<CardStackPageTransitionsBuilder>(),
    );
    expect(
      AppPageTransitions.builderFor(TransitionStyle.none, platform),
      isA<InstantPageTransitionsBuilder>(),
    );
    // Every value is covered above; the switch is exhaustive, so a new
    // value cannot be added without landing here.
    expect(TransitionStyle.values.length, _kAuthored.length + 2);
  });

  test('the shipped value is what ships, and the catalog says so', () {
    expect(TransitionStyle.values.first, TransitionStyle.platformDefault);
    expect(TransitionStyle.fromWire(null), TransitionStyle.platformDefault);
    expect(
      TransitionStyle.fromWire('not-a-value'),
      TransitionStyle.platformDefault,
    );

    final entry = kMotionFormats.firstWhere(
      (format) => format.slot == CombatDenSlots.transitionStyle,
    );
    expect(entry.implemented, isTrue);
    expect(entry.shipped, TransitionStyle.platformDefault.name);
    expect(
      entry.values,
      TransitionStyle.values.map((value) => value.name).toList(),
    );
  });

  test('no transition authors a bounce, elastic, or anticipation curve', () {
    final dir = Directory('lib/shared/themes/transitions');
    expect(dir.existsSync(), isTrue, reason: 'the transition module moved');

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
}

// ---------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------

const double _kEpsilon = 0.01;

const String _kOriginRoute = '/';
const String _kDetailRoute = '/detail';
const String _kReplacedRoute = '/replaced';
const String _kPagerRoute = '/pager';
const String _kProfileRoute = '/profile';

const ValueKey<String> _kOriginKey = ValueKey('origin-screen');
const ValueKey<String> _kDetailKey = ValueKey('detail-screen');
const ValueKey<String> _kReplacedKey = ValueKey('replaced-screen');
const ValueKey<String> _kPagerKey = ValueKey('pager-screen');

const String _kPushLabel = 'open detail';
const String _kReplaceLabel = 'replace this screen';
const String _kPagerLabel = 'open pager';
const String _kProfileLabel = 'open profile';
const String _kPopLabel = 'go back';

const List<String> _kPagerPages = ['page one', 'page two', 'page three'];

/// Everything the detail fixture renders. Derived from the fixture's own
/// data rather than transcribed from it, so a change to the fixture
/// moves the contract with it.
const List<String> _kDetailTexts = [
  'Detail heading',
  'Detail body copy',
  'Detail footnote',
];

final List<String> _kDetailContract = [..._kDetailTexts, _kPopLabel]..sort();

/// The values that author a transition. `platformDefault` is the
/// framework's and `none` is a cut, so neither is held to the floor.
const List<TransitionStyle> _kAuthored = [
  TransitionStyle.fade,
  TransitionStyle.sharedAxis,
  TransitionStyle.cardStack,
];

/// The box each authored value's motion has to stay inside, expressed
/// as fractions of the screen and read off the builders themselves so
/// the gate follows the values rather than duplicating them.
class _Envelope {
  const _Envelope({
    this.fromX = 0,
    this.fromY = 0,
    this.leavingX = 0,
    this.leavingScale = 1,
  });

  /// Where the arriving screen starts, as a fraction of the width.
  final double fromX;

  /// Where the arriving screen starts, as a fraction of the height.
  final double fromY;

  /// How far the covered screen slides away, as a fraction of the width.
  final double leavingX;

  /// The smallest scale the covered screen reaches.
  final double leavingScale;
}

const Map<TransitionStyle, _Envelope> _kEnvelopes = {
  TransitionStyle.fade: _Envelope(),
  TransitionStyle.sharedAxis: _Envelope(
    fromX: SharedAxisPageTransitionsBuilder.travel,
    leavingX: SharedAxisPageTransitionsBuilder.travel,
  ),
  TransitionStyle.cardStack: _Envelope(
    fromY: CardStackPageTransitionsBuilder.rise,
    leavingScale: CardStackPageTransitionsBuilder.recede,
  ),
};

class _OriginFixture extends StatelessWidget {
  const _OriginFixture();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _kOriginKey,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(_kDetailRoute),
              child: const Text(_kPushLabel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed(_kReplacedRoute),
              child: const Text(_kReplaceLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamed(_kPagerRoute),
              child: const Text(_kPagerLabel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(_kProfileRoute),
              child: const Text(_kProfileLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailFixture extends StatelessWidget {
  const _DetailFixture();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _kDetailKey,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in _kDetailTexts) Text(line),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(_kPopLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplacedFixture extends StatelessWidget {
  const _ReplacedFixture();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: _kReplacedKey,
      body: Center(child: Text('replaced')),
    );
  }
}

/// Stands in for every screen that owns a horizontal drag of its own —
/// the home day pager, the class screen's swipe into post-class, the
/// rewards carousel.
class _PagerFixture extends StatelessWidget {
  const _PagerFixture();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _kPagerKey,
      body: PageView(
        children: [
          for (final page in _kPagerPages) Center(child: Text(page)),
        ],
      ),
    );
  }
}
