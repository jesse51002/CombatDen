import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/stub_asset_bundle.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/points/points_body.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rank/rank_body.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/reward_slide.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_body.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_body.dart';
import 'package:mobile_app/features/stats/presentation/widgets/wins/wins_body.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_close.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_cta.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_stage.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// The functional-equivalence gate for `celebration_format`.
///
/// A layout format may change ARRANGEMENT ONLY. This asserts it
/// mechanically: every value of the enum is pumped and its element set is
/// compared against the contract below, then the intro contract — CTA
/// inert while the body animates, live after `markDone`, tap-to-skip
/// reaching the body — is exercised on each. A generated layout that
/// drops the close action, renders a second CTA, or forgets to wrap the
/// body in the skip target fails here rather than in review.
///
/// The second half pumps all five REAL post-class cards through all five
/// values at true phone size, which is what catches an arrangement that
/// only overflows once a real body's height is in it.
void main() {
  const bodyKey = Key('celebration-body');
  const headerKey = Key('celebration-header');

  /// Pump at a real phone size. At the default 800x600 test surface a
  /// cramped column still fits, so an arrangement that overflows on an
  /// actual device would pass unnoticed.
  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child) {
    return DefaultAssetBundle(
      bundle: StubAssetBundle(),
      child: MaterialApp(home: child),
    );
  }

  Widget card({
    required CelebrationFormat format,
    Widget? body,
    PostClassController? controller,
    VoidCallback? onClose,
    VoidCallback? onCtaPressed,
    bool withHeader = true,
  }) {
    return host(
      PostClassScaffold(
        formatOverride: format,
        controller: controller,
        header: withHeader
            ? const Text('Nice session', key: headerKey)
            : null,
        onClose: onClose,
        ctaLabel: 'Continue',
        onCtaPressed: onCtaPressed ?? () {},
        body: body ?? const _BodyStandIn(key: bodyKey),
      ),
    );
  }

  /// The CTA's fade target: 0 while the body animates, 1 once it is done.
  /// Reading the widget's own property (not the interpolated value) keeps
  /// the assertion deterministic.
  double ctaOpacity(WidgetTester tester) {
    return tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(CelebrationCta),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
  }

  bool ctaIgnoresTaps(WidgetTester tester) {
    return tester
        .widget<IgnorePointer>(
          find
              .descendant(
                of: find.byType(CelebrationCta),
                matching: find.byType(IgnorePointer),
              )
              .first,
        )
        .ignoring;
  }

  group('every celebration format carries every slot', () {
    for (final format in CelebrationFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(card(format: format, onClose: () {}));

        // The body slot, laid out through the one part that carries the
        // tap-to-skip target.
        expect(find.byType(CelebrationStage), findsOneWidget);
        expect(find.byKey(bodyKey), findsOneWidget);

        // The header, where the screen supplies one.
        expect(find.byKey(headerKey), findsOneWidget);

        // The dismiss action.
        expect(find.byType(CelebrationClose), findsOneWidget);

        // Exactly one primary action, carrying the screen's label.
        expect(find.byType(CelebrationCta), findsOneWidget);
        expect(find.byType(AppPrimaryButton), findsOneWidget);
        expect(find.text('Continue'), findsOneWidget);
      });
    }
  });

  group('the optional slots appear exactly when the screen supplies them', () {
    for (final format in CelebrationFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        await tester.pumpWidget(card(format: format, withHeader: false));

        expect(find.byType(CelebrationClose), findsNothing);
        expect(find.byKey(headerKey), findsNothing);

        // The mandatory set is untouched by the optional ones.
        expect(find.byKey(bodyKey), findsOneWidget);
        expect(find.byType(AppPrimaryButton), findsOneWidget);
      });
    }
  });

  group('the CTA is inert while the body animates', () {
    for (final format in CelebrationFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        final controller = PostClassController();
        addTearDown(controller.dispose);
        var ctaTaps = 0;

        await tester.pumpWidget(
          card(
            format: format,
            controller: controller,
            onClose: () {},
            onCtaPressed: () => ctaTaps++,
          ),
        );

        expect(controller.isAnimating, isTrue);
        expect(ctaOpacity(tester), 0);
        expect(ctaIgnoresTaps(tester), isTrue);

        await tester.tap(find.byType(AppPrimaryButton), warnIfMissed: false);
        await tester.pump();
        expect(ctaTaps, 0, reason: 'a hidden CTA must not be tappable');

        controller.markDone();
        await tester.pumpAndSettle();

        expect(ctaOpacity(tester), 1);
        expect(ctaIgnoresTaps(tester), isFalse);

        await tester.tap(find.byType(AppPrimaryButton));
        await tester.pump();
        expect(ctaTaps, 1);
      });
    }
  });

  group('a tap on the body area asks the body to skip its intro', () {
    for (final format in CelebrationFormat.values) {
      testWidgets('$format', (tester) async {
        phoneSized(tester);
        final controller = PostClassController();
        addTearDown(controller.dispose);
        var skips = 0;
        controller.registerSkipHandler(() => skips++);

        await tester.pumpWidget(
          card(format: format, controller: controller, onClose: () {}),
        );

        await tester.tap(find.byType(CelebrationStage));
        await tester.pump();
        expect(skips, 1);
      });
    }
  });

  group('every format renders every post-class card at phone size', () {
    // The real bodies, so the gate measures real heights. Wins ships
    // without a controller (it has no intro), exactly as its screen does.
    final cards = <String, Widget Function(PostClassController?)>{
      'streak': (c) => StreakBody(stats: mockStreakStats, controller: c),
      'rank': (c) => RankBody(stats: mockRankStats, controller: c),
      'points': (c) => PointsBody(stats: mockPointsStats, controller: c),
      'rewards': (c) => RewardsBody(
        slides: mockRewardsStats.items.map(RewardSlide.fromMock).toList(),
        title: mockRewardsStats.title,
        subtitle: mockRewardsStats.subtitle,
        featuredIndex: mockRewardsStats.featuredIndex,
        controller: c,
      ),
      'wins': (c) => WinsBody(stats: mockWinsStats),
    };

    for (final format in CelebrationFormat.values) {
      for (final entry in cards.entries) {
        testWidgets('$format / ${entry.key}', (tester) async {
          phoneSized(tester);
          final controller = entry.key == 'wins'
              ? null
              : PostClassController();
          if (controller != null) addTearDown(controller.dispose);

          await tester.pumpWidget(
            host(
              PostClassScaffold(
                formatOverride: format,
                controller: controller,
                body: entry.value(controller),
                ctaLabel: 'Continue',
                onCtaPressed: () {},
                onClose: () {},
              ),
            ),
          );
          await tester.pump();

          // The intro state lays out at phone size without overflowing.
          expect(find.byType(CelebrationStage), findsOneWidget);
          expect(find.byType(CelebrationClose), findsOneWidget);
          expect(find.byType(AppPrimaryButton), findsOneWidget);

          if (controller != null) {
            expect(controller.isAnimating, isTrue);
            expect(ctaOpacity(tester), 0);

            // Tapping the body skips straight to the settled state.
            await tester.tap(find.byType(CelebrationStage));
            await tester.pump();
            expect(controller.isAnimating, isFalse);
          }

          // Let every staggered reveal and count-up land, so the settled
          // state is the thing measured. Four seconds clears the longest
          // cascade and stops short of the rewards carousel's 5s advance.
          await tester.pump(const Duration(seconds: 4));

          expect(find.byType(AppPrimaryButton), findsOneWidget);
          expect(find.byType(CelebrationClose), findsOneWidget);
          if (controller != null) {
            expect(ctaOpacity(tester), 1);
            expect(ctaIgnoresTaps(tester), isFalse);
          }

          // Unmount so the rewards carousel's pending advance is cancelled.
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  });
}

/// Stand-in for a card's body: one opaque block, the same shape every
/// layout has to place. Deliberately not interactive, so a tap on it
/// reaches the stage's skip target.
class _BodyStandIn extends StatelessWidget {
  const _BodyStandIn({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
    );
  }
}
