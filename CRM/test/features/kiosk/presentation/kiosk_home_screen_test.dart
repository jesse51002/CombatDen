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

/// The kiosk home is a full-viewport, horizontal two-column composition
/// (QR half | vertical "or" seam | name-search half) with a big title above
/// and a sign-up entry below. This proves it renders at iPad-landscape size
/// with no layout exception — the seam + `IntrinsicHeight` + stretch interplay
/// is the fragile part — and that the mockup's copy is on screen.
void main() {
  late KioskFlowCubit cubit;

  setUp(() {
    // The home's app line is WHITE-LABELLED off the active gym, the same
    // source the kiosk header names it from.
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
    expect(find.text('New here? Sign up'), findsOneWidget);
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

      // The fix must not push "Name search" down to chase the QR — the two
      // halves' heads share a top edge.
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

      // The founder-approved departure from the mockup: the two bodies share
      // one flexible band, so they land on the SAME centre — the QR half's
      // adoption footer no longer drags the field below the code. Exact, not
      // a tolerance: nothing in the layout is measured or pixel-pinned.
      expect(fieldCenter, moreOrLessEquals(qrCenter, epsilon: 0.5));
    });

    testWidgets('that shared centre really is below both heads and above the '
        'adopt footer', (tester) async {
      await pumpHome(tester);

      final headBottom = tester
          .getRect(find.text('Scan QR code with app for instant check in'))
          .bottom;
      final adoptTop = tester.getRect(find.byType(AppPrimaryButton)).top;
      final qrCenter = tester.getRect(find.byType(KioskQrFrame)).center.dy;

      // Both bodies float in the middle band rather than stacking under their
      // heads, and the footer stays pinned below that band.
      expect(qrCenter, greaterThan(headBottom + DesignConstants.spacingBig));
      expect(qrCenter, lessThan(adoptTop - DesignConstants.spacingBig));
    });

    testWidgets('an empty result list adds no height under the field',
        (tester) async {
      await pumpHome(tester);

      // The resting results slot must be a true zero-height box: reserving a
      // gap for it (a parent column spacing) would nudge the field off the
      // shared centre asserted above.
      expect(tester.getRect(find.byType(KioskSearchResults)).height, 0);
    });

    testWidgets('the search field is capped and centred, never run to the '
        'edge of the column', (tester) async {
      await pumpHome(tester);

      final field = tester.getRect(find.byType(AppSearchBox));
      final column = tester.getRect(find.byType(KioskNameSearch));

      // A field stretched across a whole half of an iPad reads as running off
      // the screen; it is capped at the home measure and centred in its half.
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
    // Short on purpose: the line beside it already says what and where, so
    // the button only has to carry the verb.
    expect(button.text, 'Get it');
    // The default AppPrimaryButton look IS the brand gradient — no solid
    // override, so it carries the primary colour.
    expect(button.backgroundColor, isNull);
  });

  testWidgets('the app line names the GYM\'s app, never the platform',
      (tester) async {
    await pumpHome(tester);

    expect(find.text('Get the Iron Den app in the App Store.'), findsOneWidget);
    expect(find.textContaining('CombatDen'), findsNothing);
  });

  group('the adopt strip is ONE row', () {
    testWidgets('the app line and the Get-it button share a vertical band',
        (tester) async {
      await pumpHome(tester);

      final line = tester.getRect(find.byType(KioskAppLine));
      final button = tester.getRect(find.byType(AppPrimaryButton));

      // Side by side, not stacked: the sentence sits LEFT of the button, and
      // the two ride one centre line.
      expect(line.right, lessThanOrEqualTo(button.left));
      expect(line.center.dy, moreOrLessEquals(button.center.dy, epsilon: 0.5));
      // The line's whole box lies inside the button's band — the strip is one
      // row tall, and the taller of the pair is what sets that height.
      expect(line.top, greaterThanOrEqualTo(button.top));
      expect(line.bottom, lessThanOrEqualTo(button.bottom));
    });

    testWidgets('the foot is shorter than the stacked block it replaced',
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

      // Stacked, the foot was rule + gap + line + gap + button. One row drops
      // a whole line AND a gap out of the column — that height is exactly the
      // weight the search half had nothing to answer with.
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
      // The line is white-labelled, so the gym's own name decides how long it
      // runs. It must never push the button out of the column or off screen.
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
      // The founder's balance complaint: a 19px/18x34 filled button beside a
      // 17px/15x30 outline one made the QR column read far heavier than the
      // search column. "Get it" keeps its filled primary treatment and drops
      // to the secondary rung's metrics, so the pair reads as one set. This
      // asserts they stay tied together rather than drifting apart again.
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
      expect(outline.text, 'New here? Sign up');
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
