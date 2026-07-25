import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_showcase.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_dots.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_progress.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/slides/kiosk_rank_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_get_app_modal.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

class _MockKioskFlowCubit extends MockCubit<KioskFlowState>
    implements KioskFlowCubit {}

RewardResponse _reward(String title, int cost) => RewardResponse(
      rewardId: 'r-$title',
      gymId: 'gym-1',
      title: title,
      pointCost: cost,
      isActive: true,
      createdAt: DateTime.utc(2026),
    );

EffectiveClassInstance _occurrence(String name, String time, {DateTime? date}) {
  final day = date ?? DateTime.utc(2026, 7, 23);
  return EffectiveClassInstance(
    classId: 'c-$name',
    gymId: 'gym-1',
    className: name,
    classDate: day,
    originalDate: day,
    originalTime: time,
    occurredAt: DateTime.utc(day.year, day.month, day.day, 18),
    resolvedClassTime: time,
    resolvedDurationMinutes: 60,
    pointsWorth: 10,
    isCancelled: false,
    hasInstanceException: false,
    hasRangeException: false,
  );
}

Video _video(String title, {int? views, String channel = 'Combat Culture'}) =>
    Video(
      url: 'https://youtube.com/watch?v=$title',
      title: title,
      thumbnailUrl: '',
      channelName: channel,
      channelUrl: 'https://youtube.com/@cc',
      channelAvatarUrl: '',
      viewCount: views,
      relevanceIndex: 0,
      tags: const [],
      bigGroups: const [],
    );

MainRank _rank(String name, int order) => MainRank(
      rankId: 'rank-$name',
      gymId: 'gym-1',
      mainRankNumOrder: order,
      name: name,
      classesToNextMajor: 25,
      createdAt: DateTime.utc(2026),
    );

/// The "Get the app" modal: ONE solid popup surface holding two nested cards —
/// the app card (white-labelled title, benefit checks, a REAL scannable
/// download QR, the sign-in steps) beside the auto-advancing "In the app"
/// showcase — over the timer + Done foot, which sit inside that surface too.
///
/// The load-bearing rules: it FITS an iPad landscape fold with nothing
/// scrolling, the app is named after the GYM and never the platform, and every
/// slide is conditional on real gym data — omitted outright, never a stand-in.
/// The classes slide reads `showcaseClasses`, the gym-wide UPCOMING list warmed
/// at kiosk entry, so it renders on the HOME path with no member known. "Track
/// rank" alone is deliberately illustrative (founder ruling, see
/// `kiosk_rank_slide_test.dart`) and never claims a rung for the viewer.
void main() {
  // Every entry-warmed catalogue populated — true from the idle home too.
  final fullRewards = [_reward('Club t-shirt', 1500)];
  final fullClasses = [_occurrence('Muay Thai Fundamentals', '18:00:00')];
  final fullVideos = [_video('Clinch control fundamentals', views: 12000)];
  final fullLadder = kioskRankSteps(
    [_rank('White', 1), _rank('Blue', 2), _rank('Purple', 3)],
  );

  Future<_MockKioskFlowCubit> pumpModal(
    WidgetTester tester, {
    String gymId = 'gym-1',
    String? gymName = 'Iron Den',
    int secondsLeft = 60,
    String? memberEmail,
    List<RewardResponse> rewards = const [],
    List<EffectiveClassInstance> showcaseClasses = const [],
    List<Video> videos = const [],
    List<KioskRankStep> rankLadder = const [],
    ThemeMode themeMode = ThemeMode.light,
    Size surface = const Size(1180, 820),
  }) async {
    themeController.setMode(themeMode);
    addTearDown(() => themeController.setMode(ThemeMode.light));
    final cubit = _MockKioskFlowCubit();
    whenListen(
      cubit,
      const Stream<KioskFlowState>.empty(),
      initialState: const KioskFlowState.home(),
    );
    addTearDown(cubit.close);
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<KioskFlowCubit>.value(
            value: cubit,
            child: Stack(
              children: [
                KioskGetAppModal(
                  gymId: gymId,
                  gymName: gymName,
                  secondsLeft: secondsLeft,
                  memberEmail: memberEmail,
                  rewards: rewards,
                  showcaseClasses: showcaseClasses,
                  videos: videos,
                  rankLadder: rankLadder,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // let the drain bar's 1s tween finish
    return cubit;
  }

  /// The modal with every catalogue populated — the normal glance-path shape.
  Future<_MockKioskFlowCubit> pumpFull(
    WidgetTester tester, {
    String? gymName = 'Iron Den',
    String? memberEmail,
    ThemeMode themeMode = ThemeMode.light,
    Size surface = const Size(1180, 820),
  }) =>
      pumpModal(
        tester,
        gymName: gymName,
        memberEmail: memberEmail,
        themeMode: themeMode,
        surface: surface,
        rewards: fullRewards,
        showcaseClasses: fullClasses,
        videos: fullVideos,
        rankLadder: fullLadder,
      );

  /// The worst case: every slide populated and the member known, so nothing is
  /// omitted and every panel is at its tallest.
  Future<_MockKioskFlowCubit> pumpWorstCase(
    WidgetTester tester, {
    required Size surface,
  }) =>
      pumpModal(
        tester,
        surface: surface,
        memberEmail: 'marcus.bell@gmail.com',
        rewards: [
          _reward('Bring a friend', 1000),
          _reward('Club t-shirt', 1500),
          _reward('Boxing gloves', 2000),
          _reward('1-on-1 PT session', 2500),
        ],
        showcaseClasses: [
          _occurrence('Muay Thai Fundamentals', '18:00:00'),
          _occurrence('Boxing Conditioning', '19:00:00'),
        ],
        videos: [
          _video('Clinch control fundamentals', views: 12000),
          _video('Guard retention basics', views: 8400),
        ],
        rankLadder: kioskRankSteps([
          _rank('White', 1),
          _rank('Blue', 2),
          _rank('Purple', 3),
          _rank('Brown', 4),
          _rank('Black', 5),
        ]),
      );

  group('composition', () {
    testWidgets('renders both nested cards with no layout error',
        (tester) async {
      await pumpFull(tester);

      expect(tester.takeException(), isNull);
      // Left card — the app card, white-labelled after the gym.
      expect(find.text('Get the Iron Den App'), findsOneWidget);
      expect(find.text('Earn rewards'), findsWidgets);
      expect(find.text('Watch videos'), findsWidgets);
      expect(find.text('Scan to download the app'), findsOneWidget);
      expect(
        find.text('Sign in with the email you signed up with'),
        findsOneWidget,
      );
      // Right card — the showcase.
      expect(find.text('IN THE APP'), findsOneWidget);
      // "Book classes" is both a card benefit and the first slide's title.
      expect(find.text('Book classes'), findsNWidgets(2));
      // Foot.
      expect(find.text('Back to start in 60s'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('lays the app card left of the showcase', (tester) async {
      await pumpFull(tester);

      final cardX = tester.getCenter(find.text('Get the Iron Den App')).dx;
      final showcaseX = tester.getCenter(find.text('IN THE APP')).dx;

      expect(cardX, lessThan(showcaseX));
    });

    testWidgets('the auto-rotate note lists exactly the live slides',
        (tester) async {
      await pumpFull(tester);

      expect(
        find.text(
          'Auto-rotates: book classes · earn rewards · watch videos · '
          'track rank',
        ),
        findsOneWidget,
      );
    });
  });

  group('ONE solid popup, two nested cards, Done inside', () {
    testWidgets('the popup is a real surface, not two panels on the veil',
        (tester) async {
      await pumpFull(tester);

      final popup = tester.widget<Container>(find.byKey(kKioskGetAppPopup));
      final decoration = popup.decoration as BoxDecoration;
      // The kiosk's own popup chrome — the same one the idle warning wears.
      expect(decoration.color, DesignConstants.popup);
      expect(decoration.boxShadow, DesignConstants.cardShadow);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(DesignConstants.radiusCard),
      );
    });

    testWidgets('both cards AND the Done foot sit inside that surface',
        (tester) async {
      await pumpFull(tester);

      final popup = tester.getRect(find.byKey(kKioskGetAppPopup));
      final parts = <String, Finder>{
        'the app card': find.byType(KioskAppCard),
        'the showcase': find.byType(KioskAppShowcase),
        'Done': find.text('Done'),
        'the countdown': find.text('Back to start in 60s'),
      };
      parts.forEach((name, finder) {
        final rect = tester.getRect(finder);
        expect(
          popup.contains(rect.topLeft) && popup.contains(rect.bottomRight),
          isTrue,
          reason: '$name must be nested INSIDE the popup',
        );
      });
    });

    testWidgets('there is no spanning "Welcome to {gym}" header any more',
        (tester) async {
      // The gym is already named on the kiosk header and on the app card's own
      // title; a third naming only costs height on a screen that can't scroll.
      await pumpFull(tester);

      expect(find.textContaining('Welcome'), findsNothing);
    });
  });

  group('it FITS the fold — nothing scrolls', () {
    for (final fold in const <Size>[Size(1180, 820), Size(1024, 700)]) {
      testWidgets('no overflow and no vertical scroll at '
          '${fold.width.toInt()}x${fold.height.toInt()}', (tester) async {
        await pumpWorstCase(tester, surface: fold);

        // An overflow would surface here.
        expect(tester.takeException(), isNull);
        expect(find.byType(QrImageView), findsOneWidget);

        // Nothing here may scroll vertically — content below a fold is content
        // a member at a kiosk never finds. Sideways strips are fine.
        for (final scrollable
            in tester.widgetList<Scrollable>(find.byType(Scrollable))) {
          expect(
            axisDirectionToAxis(scrollable.axisDirection),
            Axis.horizontal,
            reason: 'the kiosk popup must never scroll vertically',
          );
        }

        // And it really is inside the viewport, top to bottom.
        final popup = tester.getRect(find.byKey(kKioskGetAppPopup));
        expect(popup.top, greaterThanOrEqualTo(0));
        expect(popup.bottom, lessThanOrEqualTo(fold.height));
      });
    }
  });

  group('the app is named after the GYM, never the platform', () {
    testWidgets('the card title white-labels to the gym', (tester) async {
      await pumpFull(tester, gymName: 'Ocean Pilates');

      expect(find.text('Get the Ocean Pilates App'), findsOneWidget);
      expect(find.textContaining('CombatDen'), findsNothing);
    });

    testWidgets('an unknown gym name degrades to a neutral title, never an '
        'empty or broken one', (tester) async {
      await pumpFull(tester, gymName: null);

      expect(find.text('Get the App'), findsOneWidget);
      expect(find.textContaining('  '), findsNothing);
    });

    testWidgets('a blank gym name is treated as no name at all',
        (tester) async {
      await pumpFull(tester, gymName: '   ');

      expect(find.text('Get the App'), findsOneWidget);
    });

    testWidgets('the title is a kiosk PANEL title, one step under a screen '
        'title', (tester) async {
      await pumpFull(tester);

      final title = tester.widget<Text>(find.text('Get the Iron Den App'));
      expect(title.style, DesignConstants.kioskPanelTitle);
    });
  });

  group('the download QR', () {
    test('kioskAppDownloadUrl builds the per-gym app-download page URL', () {
      expect(kKioskAppDownloadBaseUrl, 'https://www.combatden.net/get-app');
      expect(
        kioskAppDownloadUrl('gym-xyz'),
        'https://www.combatden.net/get-app/gym-xyz',
      );
    });

    testWidgets('renders a single real QR (the scannable download code)',
        (tester) async {
      await pumpFull(tester);

      // `QrImageView` keeps its payload private, so the URL is pinned by the
      // unit test above; this only proves one real code, not the placeholder.
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('stays fixed dark-on-white under the DARK theme',
        (tester) async {
      await pumpFull(tester, themeMode: ThemeMode.dark);

      // Sanity: the surrounding theme really is dark for this pump.
      expect(themeController.isDark, isTrue);

      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      // A QR must stay dark-on-light for a scanner — it is pinned to the fixed
      // kiosk tokens, NOT the theme's surface/text (which would invert it).
      expect(qr.backgroundColor, DesignConstants.kioskQrQuietZone);
      expect(qr.dataModuleStyle.color, DesignConstants.kioskQrModule);
      expect(qr.eyeStyle.color, DesignConstants.kioskQrModule);
      expect(qr.backgroundColor, isNot(DesignConstants.surface));
      expect(qr.dataModuleStyle.color, isNot(DesignConstants.text));
    });
  });

  group('sign-in step 2', () {
    testWidgets('shows the address only when the member is known',
        (tester) async {
      await pumpFull(tester, memberEmail: 'marcus.bell@gmail.com');

      expect(find.text('marcus.bell@gmail.com'), findsOneWidget);
    });

    testWidgets('omits the address when no member is known', (tester) async {
      await pumpFull(tester);

      // The step still renders — just with no stand-in address under it.
      expect(
        find.text('Sign in with the email you signed up with'),
        findsOneWidget,
      );
      expect(find.textContaining('@'), findsNothing);
    });
  });

  group('every slide is conditional on the gym\'s REAL data', () {
    testWidgets('present: each slide renders the gym\'s own content',
        (tester) async {
      await pumpFull(tester);

      // Classes — the real occurrences the flow loaded.
      expect(find.text('Muay Thai Fundamentals'), findsOneWidget);
      // Rewards — the real catalogue.
      expect(find.text('Club t-shirt'), findsOneWidget);
      expect(find.text('1,500 pts'), findsOneWidget);
      // Videos — THIS gym's own curated feed, with its real view count.
      expect(find.text('Clinch control fundamentals'), findsOneWidget);
      expect(find.text('12K views'), findsOneWidget);
      // Ranks — the gym's real belt names; the featured rung is illustrative,
      // so nothing claims it for the person standing there.
      expect(find.text('Blue'), findsOneWidget);
      expect(find.byType(KioskRankProgress), findsOneWidget);
      expect(find.text('You\'re here'), findsNothing);
      // Four slides -> four dots.
      expect(
        find.descendant(
          of: find.byType(KioskShowcaseDots),
          matching: find.byType(GestureDetector),
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('absent: a gym with no video feed loses the slide, its dot '
        'and its mention', (tester) async {
      await pumpModal(
        tester,
        rewards: fullRewards,
        showcaseClasses: fullClasses,
        rankLadder: fullLadder,
      );

      expect(find.text('Clinch control fundamentals'), findsNothing);
      // "Watch videos" survives ONLY as an app-card benefit check, never as a
      // slide title or a rotation caption.
      expect(find.text('Watch videos'), findsOneWidget);
      expect(
        find.text(
          'Auto-rotates: book classes · earn rewards · track rank',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(KioskShowcaseDots),
          matching: find.byType(GestureDetector),
        ),
        findsNWidgets(3),
      );
    });

    testWidgets('absent: a gym that doesn\'t run ranks never sees belts',
        (tester) async {
      await pumpModal(
        tester,
        rewards: fullRewards,
        showcaseClasses: fullClasses,
        videos: fullVideos,
      );

      expect(find.text('Track rank'), findsNothing);
      // No belts, and no rank progress bar either — the whole slide is gone.
      expect(find.text('Blue'), findsNothing);
      expect(find.byType(KioskRankProgress), findsNothing);
      expect(
        find.text('Auto-rotates: book classes · earn rewards · watch videos'),
        findsOneWidget,
      );
    });

    testWidgets('present from the HOME path: the classes slide renders with '
        'no member known', (tester) async {
      // The classes are the gym-wide UPCOMING list warmed at kiosk entry, so
      // the slide is there before anyone has typed a name.
      await pumpFull(tester, memberEmail: null);

      expect(find.text('Muay Thai Fundamentals'), findsOneWidget);
      expect(find.text('Book classes'), findsNWidgets(2)); // benefit + slide
      expect(
        find.text(
          'Auto-rotates: book classes · earn rewards · watch videos · '
          'track rank',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(KioskShowcaseDots),
          matching: find.byType(GestureDetector),
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('absent: a gym that runs no classes loses the slide, its dot '
        'and its mention', (tester) async {
      // A wider showcase window must never invent a class for a gym with none.
      await pumpModal(
        tester,
        rewards: fullRewards,
        videos: fullVideos,
      );

      expect(find.text('Muay Thai Fundamentals'), findsNothing);
      // "Book classes" survives ONLY as an app-card benefit check.
      expect(find.text('Book classes'), findsOneWidget);
      expect(
        find.text('Auto-rotates: earn rewards · watch videos'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(KioskShowcaseDots),
          matching: find.byType(GestureDetector),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('the row states the class\'s REAL day, never a fixed "Today"',
        (tester) async {
      // The showcase looks a week ahead, so the day word is read off each
      // occurrence's own date — a fixed "Today" would be an invented fact.
      final today = DateTime.now();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      await pumpModal(
        tester,
        showcaseClasses: [
          _occurrence('Muay Thai Fundamentals', '18:00:00', date: today),
          _occurrence('Boxing Conditioning', '19:00:00', date: tomorrow),
        ],
      );

      // The time half is `DateFormat.jm()`'s own output (its AM/PM separator
      // is locale data, not ours) — the day word is what this pins.
      expect(find.textContaining('Today · '), findsOneWidget);
      expect(find.textContaining('Tomorrow · '), findsOneWidget);
    });

    testWidgets('invents no gym content when the kiosk holds none',
        (tester) async {
      await pumpModal(tester);

      // No demo row, reward, video or belt ever ships as if it were real.
      expect(find.text('Muay Thai Fundamentals'), findsNothing);
      expect(find.text('Bring a friend'), findsNothing);
      expect(find.text('Clinch control fundamentals'), findsNothing);
      expect(find.byType(KioskRankProgress), findsNothing);
      // With nothing to show the showcase card is dropped outright.
      expect(find.byType(KioskAppShowcase), findsNothing);
      expect(find.text('IN THE APP'), findsNothing);
      expect(find.text('Get the Iron Den App'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the showcase rotates', () {
    // Each title appears once as an app-card benefit; the ACTIVE slide adds a
    // second copy as the showcase head. A count of 2 means "showing".
    testWidgets('auto-advances to the next slide after the dwell',
        (tester) async {
      await pumpFull(tester);

      expect(find.text('Book classes'), findsNWidgets(2));
      expect(find.text('Earn rewards'), findsOneWidget);

      await tester.pump(kKioskShowcaseInterval);
      await tester.pump(kKioskShowcaseFade);

      expect(find.text('Book classes'), findsOneWidget);
      expect(find.text('Earn rewards'), findsNWidgets(2));
    });

    testWidgets('a dot jumps straight to its slide', (tester) async {
      await pumpFull(tester);

      final dots = find.descendant(
        of: find.byType(KioskShowcaseDots),
        matching: find.byType(GestureDetector),
      );
      expect(dots, findsNWidgets(4));

      await tester.tap(dots.at(2)); // "Watch videos"
      await tester.pump();
      await tester.pump(kKioskShowcaseFade);

      expect(find.text('Watch videos'), findsNWidgets(2));
      expect(find.text('Book classes'), findsOneWidget);
    });
  });

  group('modal behaviour is preserved', () {
    testWidgets('the foot timer reflects the cubit countdown', (tester) async {
      await pumpModal(tester, secondsLeft: 42);

      expect(find.text('Back to start in 42s'), findsOneWidget);
    });

    testWidgets('Done closes the modal via the cubit', (tester) async {
      final cubit = await pumpFull(tester);

      await tester.tap(find.text('Done'));
      await tester.pump();

      verify(() => cubit.closeAppModal()).called(1);
    });

    testWidgets('a tap on the veil does NOT close it', (tester) async {
      final cubit = await pumpFull(tester);

      // Top-left corner of the scrim, clear of both panels.
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();

      verifyNever(() => cubit.closeAppModal());
      verifyNever(() => cubit.goHome());
    });

    testWidgets('Done runs at kiosk button scale', (tester) async {
      await pumpFull(tester);

      final done = tester.widget<AppOutlineButton>(
        find.byType(AppOutlineButton),
      );
      expect(done.text, 'Done');
      expect(done.textStyle, DesignConstants.kioskButtonOutlineLabel);
      expect(done.padding, DesignConstants.kioskButtonOutlinePadding);
    });
  });
}
