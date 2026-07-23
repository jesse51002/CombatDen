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
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_app_showcase.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_dots.dart';
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

EffectiveClassInstance _occurrence(String name, String time) =>
    EffectiveClassInstance(
      classId: 'c-$name',
      gymId: 'gym-1',
      className: name,
      classDate: DateTime.utc(2026, 7, 23),
      originalDate: DateTime.utc(2026, 7, 23),
      originalTime: time,
      occurredAt: DateTime.utc(2026, 7, 23, 18),
      resolvedClassTime: time,
      resolvedDurationMinutes: 60,
      pointsWorth: 10,
      isCancelled: false,
      hasInstanceException: false,
      hasRangeException: false,
    );

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

/// The "Get the CombatDen App" modal (UX-5) IS the approved kiosk welcome
/// screen: a spanning gym header over the accent-soft app card (title, benefit
/// checks, a REAL scannable download QR, the sign-in steps) beside the
/// auto-advancing "In the app" showcase, over the shared 60-second timer +
/// Done foot.
///
/// These prove the composition lays out at iPad-landscape size with no
/// exception, that the header states only what the kiosk really knows, that
/// EVERY showcase slide is conditional on real data (present when the gym has
/// it, omitted outright when it doesn't — never a stand-in), that the QR keeps
/// its fixed dark-on-white contrast even under the dark theme, and that the
/// modal's existing behaviour (timer label, Done → cubit) survives.
void main() {
  // The realistic populated case: the modal opened off a glance, so the flow
  // holds classes AND the entry-warmed catalogues are all in.
  final fullRewards = [_reward('Club t-shirt', 1500)];
  final fullClasses = [_occurrence('Muay Thai Fundamentals', '18:00:00')];
  final fullVideos = [_video('Clinch control fundamentals', views: 12000)];
  final fullLadder = kioskRankSteps(
    [_rank('White', 1), _rank('Blue', 2), _rank('Purple', 3)],
    currentRankId: 'rank-Blue',
  );

  Future<_MockKioskFlowCubit> pumpModal(
    WidgetTester tester, {
    String gymId = 'gym-1',
    String? gymName = 'Iron Den',
    int secondsLeft = 60,
    String? memberEmail,
    List<RewardResponse> rewards = const [],
    List<EffectiveClassInstance> classes = const [],
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
                  classes: classes,
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
        classes: fullClasses,
        videos: fullVideos,
        rankLadder: fullLadder,
      );

  group('composition', () {
    testWidgets('renders the header and both welcome panels with no layout '
        'error', (tester) async {
      await pumpFull(tester);

      expect(tester.takeException(), isNull);
      // Spanning header.
      expect(find.text('Welcome to Iron Den'), findsOneWidget);
      // Left panel — the app card.
      expect(find.text('Get the CombatDen App'), findsOneWidget);
      expect(find.text('Earn rewards'), findsWidgets);
      expect(find.text('Watch videos'), findsWidgets);
      expect(find.text('Scan to download the app'), findsOneWidget);
      expect(
        find.text('Sign in with the email you signed up with'),
        findsOneWidget,
      );
      // Right panel — the showcase.
      expect(find.text('IN THE APP'), findsOneWidget);
      // "Book classes" is both a card benefit and the first slide's title.
      expect(find.text('Book classes'), findsNWidgets(2));
      // Foot.
      expect(find.text('Back to start in 60s'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('lays the app card left of the showcase', (tester) async {
      await pumpFull(tester);

      final cardX = tester.getCenter(find.text('Get the CombatDen App')).dx;
      final showcaseX = tester.getCenter(find.text('IN THE APP')).dx;

      expect(cardX, lessThan(showcaseX));
    });

    testWidgets('fits a short iPad fold with every slide populated',
        (tester) async {
      // Worst case: all four slides carry content, on the smallest landscape
      // fold the kiosk targets (minus the persistent kiosk header).
      await pumpModal(
        tester,
        surface: const Size(1024, 700),
        memberEmail: 'marcus.bell@gmail.com',
        rewards: [
          _reward('Bring a friend', 1000),
          _reward('Club t-shirt', 1500),
          _reward('Boxing gloves', 2000),
          _reward('1-on-1 PT session', 2500),
        ],
        classes: [
          _occurrence('Muay Thai Fundamentals', '18:00:00'),
          _occurrence('Boxing Conditioning', '19:00:00'),
        ],
        videos: [
          _video('Clinch control fundamentals', views: 12000),
          _video('Guard retention basics', views: 8400),
        ],
        rankLadder: kioskRankSteps(
          [
            _rank('White', 1),
            _rank('Blue', 2),
            _rank('Purple', 3),
            _rank('Brown', 4),
            _rank('Black', 5),
          ],
          currentRankId: 'rank-Blue',
        ),
      );

      // No overflow anywhere — the body scrolls rather than clipping the QR.
      expect(tester.takeException(), isNull);
      expect(find.byType(QrImageView), findsOneWidget);
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

  group('the spanning header', () {
    testWidgets('names the gym the kiosk is running at', (tester) async {
      await pumpFull(tester, gymName: 'Ocean Pilates');

      expect(find.text('Welcome to Ocean Pilates'), findsOneWidget);
    });

    testWidgets('never carries a member name, even off the glance',
        (tester) async {
      await pumpFull(tester, memberEmail: 'marcus.bell@gmail.com');

      // The mockup's post-signup "Welcome to Iron Den, Marcus!" is not
      // reusable here: the modal also opens from the idle home.
      expect(find.text('Welcome to Iron Den'), findsOneWidget);
      expect(find.textContaining('Marcus'), findsNothing);
    });

    testWidgets('drops the gym clause rather than inventing one when the name '
        'is unknown', (tester) async {
      await pumpFull(tester, gymName: null);

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.textContaining('Welcome to'), findsNothing);
    });

    testWidgets('is a kiosk-scale line, matching the glance greeting',
        (tester) async {
      await pumpFull(tester);

      final header = tester.widget<Text>(find.text('Welcome to Iron Den'));
      expect(header.style, DesignConstants.kioskDisplay);
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

      // One real qr_flutter code (not the home glyph placeholder); it is fed
      // kioskAppDownloadUrl(gymId), whose output is asserted above —
      // QrImageView keeps its payload private, so it can't be read back here.
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
      // Ranks — the real ladder, with the member's rung tagged.
      expect(find.text('Blue'), findsOneWidget);
      expect(find.text('You\'re here'), findsOneWidget);
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
        classes: fullClasses,
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
        classes: fullClasses,
        videos: fullVideos,
      );

      expect(find.text('Track rank'), findsNothing);
      expect(find.text('You\'re here'), findsNothing);
      expect(
        find.text('Auto-rotates: book classes · earn rewards · watch videos'),
        findsOneWidget,
      );
    });

    testWidgets('absent: opened from the idle home, the classes slide is off '
        '(no member has picked one)', (tester) async {
      await pumpModal(
        tester,
        rewards: fullRewards,
        videos: fullVideos,
      );

      expect(find.text('Muay Thai Fundamentals'), findsNothing);
      expect(
        find.text('Auto-rotates: earn rewards · watch videos'),
        findsOneWidget,
      );
    });

    testWidgets('invents no gym content when the kiosk holds none',
        (tester) async {
      await pumpModal(tester);

      // The mockup's demo rows/rewards/videos/belts must never ship as if they
      // were real, and no stand-in slide takes their place.
      expect(find.text('Muay Thai Fundamentals'), findsNothing);
      expect(find.text('Bring a friend'), findsNothing);
      expect(find.text('Clinch control fundamentals'), findsNothing);
      expect(find.text('You\'re here'), findsNothing);
      // With nothing to show, the showcase panel is dropped outright and the
      // app card carries the screen alone.
      expect(find.byType(KioskAppShowcase), findsNothing);
      expect(find.text('IN THE APP'), findsNothing);
      expect(find.text('Get the CombatDen App'), findsOneWidget);
      expect(find.text('Welcome to Iron Den'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the showcase rotates', () {
    // "Book classes" / "Earn rewards" each appear once as an app-card benefit;
    // the ACTIVE slide adds a second copy as the showcase head's title. So a
    // count of 2 means "this slide is showing".
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
