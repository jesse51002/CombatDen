import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_state.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_home_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_adopt_strip.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_app_line.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_home_columns.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_name_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_qr_frame.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_search_results.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members/data/gym_content_repository.dart';
import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/models/rank_enabled_response.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_search_box.dart';
import 'package:crm/shared/widgets/hairline.dart';

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockRewardsRepository extends Mock implements RewardsRepository {}

class _MockGymContentRepository extends Mock
    implements GymContentRepository {}

class _MockRanksRepository extends Mock implements RanksRepository {}

class _MockKioskSessionCubit extends Mock implements KioskSessionCubit {}

/// The kiosk home: a full-viewport two-column composition (QR half | vertical
/// "or" seam | name-search half) under a big title, with a sign-up entry and a
/// full-width app-adoption strip closing the screen. The seam +
/// `IntrinsicHeight` + stretch interplay is the fragile part.
void main() {
  late KioskFlowCubit cubit;

  setUp(() {
    // The home's app line is WHITE-LABELLED off the active gym.
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Iron Den',
      role: EmployeeRole.owner,
      timezone: 'America/Chicago',
      logoUrl: null,
    );
    final session = _MockKioskSessionCubit();
    when(() => session.state).thenReturn(
      KioskSessionState(
        status: KioskStatus.active,
        deadline: DateTime.utc(2026, 1, 1, 30),
      ),
    );
    final rewards = _MockRewardsRepository();
    when(() => rewards.listRewards(any(),
            includeInactive: any(named: 'includeInactive')))
        .thenAnswer((_) async => const <RewardResponse>[]);
    final content = _MockGymContentRepository();
    when(() => content.fetchVideos(any(),
            videoType: any(named: 'videoType'),
            rejected: any(named: 'rejected'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset')))
        .thenAnswer((_) async => const VideoPage(videos: [], total: 0));
    final ranks = _MockRanksRepository();
    when(() => ranks.getRankEnabled(any())).thenAnswer(
      (_) async => const RankEnabledResponse(
        gymId: 'gym-1',
        isRankEnabled: false,
      ),
    );
    cubit = KioskFlowCubit(
      membersRepository: _MockMembersListRepository(),
      scheduleRepository: _MockScheduleRepository(),
      memberRepository: _MockMemberRepository(),
      rewardsRepository: rewards,
      gymContentRepository: content,
      ranksRepository: ranks,
      session: session,
      gymId: 'gym-1',
    );
  });

  tearDown(() => cubit.close());

  Future<void> pumpHome(
    WidgetTester tester, {
    ThemeMode themeMode = ThemeMode.light,
    Size size = const Size(1180, 760),
  }) async {
    themeController.setMode(themeMode);
    addTearDown(() => themeController.setMode(ThemeMode.light));
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<KioskFlowCubit>.value(
            value: cubit,
            child: const KioskHomeScreen(),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the two-column check-in home with no layout error',
      (tester) async {
    await pumpHome(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.text('Scan with app'), findsOneWidget);
    expect(find.text('Name search'), findsOneWidget);
    expect(find.text('or'), findsOneWidget);
    expect(find.text('Start Trial / Membership'), findsOneWidget);
  });

  testWidgets('lays the two halves side by side with the seam between them',
      (tester) async {
    await pumpHome(tester);

    final qrX = tester.getCenter(find.text('Scan with app')).dx;
    final seamX = tester.getCenter(find.text('or')).dx;
    final searchX = tester.getCenter(find.text('Name search')).dx;

    // QR half left of the seam, name-search half right of it (horizontal).
    expect(qrX, lessThan(seamX));
    expect(seamX, lessThan(searchX));
  });

  group('column balance (the co-centred bands)', () {
    testWidgets('both headings stay top-aligned with each other',
        (tester) async {
      await pumpHome(tester);

      // Neither head chases the other down: the two share a top edge.
      expect(
        tester.getTopLeft(find.text('Name search')).dy,
        tester.getTopLeft(find.text('Scan with app')).dy,
      );
    });

    testWidgets('the QR and the search field sit on ONE optical centre',
        (tester) async {
      await pumpHome(tester);

      final qrCenter = tester.getRect(find.byType(KioskQrFrame)).center.dy;
      final fieldCenter = tester.getRect(find.byType(AppSearchBox)).center.dy;

      // The two bodies share ONE flexible band, so they land on the SAME
      // centre. Exact, not a tolerance — nothing here is pixel-pinned.
      expect(fieldCenter, moreOrLessEquals(qrCenter, epsilon: 0.5));
    });

    testWidgets('that shared centre floats in a middle band that runs to the '
        'bottom of the columns', (tester) async {
      await pumpHome(tester);

      final headBottom = math.max(
        tester
            .getRect(find.text('Scan QR code with app for instant check in'))
            .bottom,
        tester
            .getRect(find.text('Search for your name for a quick check in'))
            .bottom,
      );
      final columns = tester.getRect(find.byType(KioskHomeColumns));
      final qrCenter = tester.getRect(find.byType(KioskQrFrame)).center.dy;
      final bandTop = headBottom + DesignConstants.spacingBig;

      // The bodies float in the middle band rather than stacking under their
      // heads...
      expect(qrCenter, greaterThan(bandTop));
      // ...and that band runs to the bottom of the composition, so the QR sits
      // on its exact midpoint — a reserved foot band would lift it off.
      expect(
        qrCenter,
        moreOrLessEquals((bandTop + columns.bottom) / 2, epsilon: 0.5),
      );
    });

    testWidgets('an empty result list adds no height under the field',
        (tester) async {
      await pumpHome(tester);

      // A true zero-height box: any gap reserved for it would nudge the field
      // off the shared centre asserted above.
      expect(tester.getRect(find.byType(KioskSearchResults)).height, 0);
    });

    testWidgets('the search field is capped and centred, never run to the '
        'edge of the column', (tester) async {
      await pumpHome(tester);

      final field = tester.getRect(find.byType(AppSearchBox));
      final column = tester.getRect(find.byType(KioskNameSearch));

      // A field run across a whole half of an iPad reads as running off screen.
      expect(field.width, DesignConstants.kioskHomeMeasure);
      expect(field.width, lessThan(column.width));
      expect(
        field.center.dx,
        moreOrLessEquals(column.center.dx, epsilon: 0.5),
      );
    });
  });

  testWidgets('the "Get it" affordance is the PRIMARY button', (tester) async {
    await pumpHome(tester);

    expect(find.byType(AppPrimaryButton), findsOneWidget);
    final button = tester.widget<AppPrimaryButton>(
      find.byType(AppPrimaryButton),
    );
    // Short on purpose: the line beside it already says what and where.
    expect(button.text, 'Get it');
    // No solid override: the default AppPrimaryButton look IS the gradient.
    expect(button.backgroundColor, isNull);
  });

  testWidgets('the app line names the GYM\'s app, never the platform',
      (tester) async {
    await pumpHome(tester);

    expect(find.text('Get the Iron Den app in the App Store.'), findsOneWidget);
    expect(find.textContaining('CombatDen'), findsNothing);
  });

  group('the adopt strip SPANS both columns', () {
    testWidgets('it is as wide as the whole composition, not one column',
        (tester) async {
      await pumpHome(tester);

      final strip = tester.getRect(find.byType(KioskAdoptStrip));
      final columns = tester.getRect(find.byType(KioskHomeColumns));
      final qr = tester.getRect(find.byType(KioskQrFrame));
      final field = tester.getRect(find.byType(AppSearchBox));

      // Getting the app is a property of the whole screen: the full stage.
      expect(strip.width, moreOrLessEquals(columns.width, epsilon: 0.5));
      // Materially wider than one column — seam and gutters included, a column
      // is under 55% of the composition.
      expect(strip.width, greaterThan(columns.width * 0.55));
      // Centred on the STAGE, reaching past the content of BOTH halves.
      expect(
        strip.center.dx,
        moreOrLessEquals(columns.center.dx, epsilon: 0.5),
      );
      expect(strip.center.dx, greaterThan(qr.center.dx));
      expect(strip.left, lessThan(qr.left));
      expect(strip.right, greaterThan(field.right));
    });

    testWidgets('it is the LAST band, below the sign-up entry',
        (tester) async {
      await pumpHome(tester);

      final columns = tester.getRect(find.byType(KioskHomeColumns));
      final signup = tester.getRect(find.byType(AppOutlineButton));
      final strip = tester.getRect(find.byType(KioskAdoptStrip));

      // Sign-up answers someone BLOCKED (no account yet); the strip is a nudge
      // nobody is waiting on, so it closes the screen rather than splitting it.
      expect(signup.top, greaterThan(columns.bottom));
      expect(strip.top, greaterThan(signup.bottom));
    });

    testWidgets('no empty foot band is reserved under the columns',
        (tester) async {
      await pumpHome(tester);

      final columns = tester.getRect(find.byType(KioskHomeColumns));
      final signup = tester.getRect(find.byType(AppOutlineButton));

      // With neither half carrying a foot the band collapses and hands its
      // height to the shared middle, leaving only the section spacing.
      expect(
        signup.top - columns.bottom,
        moreOrLessEquals(DesignConstants.spacingBig, epsilon: 0.5),
      );
    });

    testWidgets('the pair stays centred as a GROUP, never marooned at the '
        'band\'s edges', (tester) async {
      await pumpHome(tester);

      final strip = tester.getRect(find.byType(KioskAdoptStrip));
      final line = tester.getRect(find.byType(KioskAppLine));
      final button = tester.getRect(find.byType(AppPrimaryButton));
      final pair = line.expandToInclude(button);

      // The row holds them at its own spacing, never one at each end.
      expect(
        button.left - line.right,
        moreOrLessEquals(DesignConstants.spacingLarge, epsilon: 0.5),
      );
      // Capped, and centred on the strip's centre line.
      expect(
        pair.width,
        lessThanOrEqualTo(DesignConstants.kioskAdoptMeasure + 0.5),
      );
      expect(pair.width, lessThan(strip.width));
      expect(pair.center.dx, moreOrLessEquals(strip.center.dx, epsilon: 0.5));
    });
  });

  group('the adopt strip is ONE row', () {
    testWidgets('the app line and the Get-it button share a vertical band',
        (tester) async {
      await pumpHome(tester);

      final line = tester.getRect(find.byType(KioskAppLine));
      final button = tester.getRect(find.byType(AppPrimaryButton));

      // Side by side, not stacked, riding one centre line.
      expect(line.right, lessThanOrEqualTo(button.left));
      expect(line.center.dy, moreOrLessEquals(button.center.dy, epsilon: 0.5));
      // The line's whole box lies inside the button's band: one row tall.
      expect(line.top, greaterThanOrEqualTo(button.top));
      expect(line.bottom, lessThanOrEqualTo(button.bottom));
    });

    testWidgets('the strip is shorter than the stacked block it replaced',
        (tester) async {
      await pumpHome(tester);

      final strip = tester.getRect(find.byType(KioskAdoptStrip)).height;
      final rule = tester
          .getRect(
            find.descendant(
              of: find.byType(KioskAdoptStrip),
              matching: find.byType(Hairline),
            ),
          )
          .height;
      final line = tester.getRect(find.byType(KioskAppLine)).height;
      final button = tester.getRect(find.byType(AppPrimaryButton)).height;

      // Stacked it would be rule + gap + line + gap + button.
      const gap = DesignConstants.spacingLarge;
      expect(strip, lessThan(rule + gap + line + gap + button));
      // Concretely: the row band is the TALLER of the pair, never their sum.
      expect(
        strip,
        moreOrLessEquals(rule + gap + math.max(line, button), epsilon: 0.5),
      );
    });

    testWidgets('a long gym name narrows the sentence, never the button',
        (tester) async {
      // The gym's own name decides how long the line runs.
      selectedGym.setActiveGym(
        gymId: 'gym-1',
        displayName: 'Northside Brazilian Jiu-Jitsu & Fitness Academy',
        role: EmployeeRole.owner,
        timezone: 'America/Chicago',
        logoUrl: null,
      );
      await pumpHome(tester, size: const Size(1024, 700));

      expect(tester.takeException(), isNull);

      final strip = tester.getRect(find.byType(KioskAdoptStrip));
      final line = tester.getRect(find.byType(KioskAppLine));
      final button = tester.getRect(find.byType(AppPrimaryButton));

      // Still one row, still inside the column.
      expect(line.center.dy, moreOrLessEquals(button.center.dy, epsilon: 0.5));
      expect(button.left, greaterThanOrEqualTo(strip.left));
      expect(button.right, lessThanOrEqualTo(strip.right));

      // The sentence is what gives: it wraps, then ellipsizes at two lines so
      // no gym name can grow the strip back into a stack.
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(KioskAppLine),
          matching: find.byType(Text),
        ),
      );
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('every kiosk button runs at kiosk scale', () {
    testWidgets('the two home buttons are the SAME size as each other',
        (tester) async {
      // Founder ruling: an outsized filled button beside a smaller outline one
      // made the QR column read heavier. "Get it" keeps its filled treatment
      // at the outline metrics, so the pair reads as one set.
      await pumpHome(tester);

      final primary = tester.widget<AppPrimaryButton>(
        find.byType(AppPrimaryButton),
      );
      final outline = tester.widget<AppOutlineButton>(
        find.byType(AppOutlineButton),
      );

      expect(primary.textStyle, outline.textStyle);
      expect(primary.padding, outline.padding);
      expect(
        tester.getRect(find.byType(AppPrimaryButton)).height,
        tester.getRect(find.byType(AppOutlineButton)).height,
      );
    });

    testWidgets('both still carry kiosk tokens, never the admin defaults',
        (tester) async {
      await pumpHome(tester);

      final primary = tester.widget<AppPrimaryButton>(
        find.byType(AppPrimaryButton),
      );
      expect(primary.textStyle, DesignConstants.kioskButtonOutlineLabel);
      expect(primary.padding, DesignConstants.kioskButtonOutlinePadding);
      expect(primary.textStyle?.fontSize, 17);

      final outline = tester.widget<AppOutlineButton>(
        find.byType(AppOutlineButton),
      );
      expect(outline.text, 'Start Trial / Membership');
      expect(outline.textStyle, DesignConstants.kioskButtonOutlineLabel);
      expect(outline.padding, DesignConstants.kioskButtonOutlinePadding);
      expect(outline.textStyle?.fontSize, 17);

      // The admin ramp is what these must NOT be.
      expect(primary.textStyle?.fontSize, isNot(DesignConstants.h3.fontSize));
      expect(outline.textStyle?.fontSize, isNot(DesignConstants.h3.fontSize));
    });
  });

  testWidgets('the home QR tile stays dark-on-white under the DARK theme',
      (tester) async {
    await pumpHome(tester, themeMode: ThemeMode.dark);

    expect(themeController.isDark, isTrue);

    // The tile's quiet zone is pinned white, never the (dark) theme surface.
    final frame = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(KioskQrFrame),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = frame.decoration as BoxDecoration;
    expect(decoration.color, DesignConstants.kioskQrQuietZone);
    expect(decoration.color, isNot(DesignConstants.surface));

    // …and the glyph on it is pinned dark ink, never the (light) theme ink.
    final glyph = tester.widget<Icon>(find.byIcon(Symbols.qr_code_2_sharp));
    expect(glyph.color, DesignConstants.kioskQrModule);
    expect(glyph.color, isNot(DesignConstants.text));
  });
}
