import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_state.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_home_screen.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_name_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_qr_frame.dart';
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
  }) async {
    themeController.setMode(themeMode);
    addTearDown(() => themeController.setMode(ThemeMode.light));
    await tester.binding.setSurfaceSize(const Size(1180, 760));
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
      final field = tester.getRect(find.byType(AppSearchBox));
      final band = tester.getRect(find.byType(KioskNameSearch));

      expect(band.height, field.height);
    });
  });

  testWidgets('the "Get it" affordance is the PRIMARY button', (tester) async {
    await pumpHome(tester);

    expect(find.byType(AppPrimaryButton), findsOneWidget);
    final button = tester.widget<AppPrimaryButton>(
      find.byType(AppPrimaryButton),
    );
    expect(button.text, 'Don\'t have the app? Get it');
    // The default AppPrimaryButton look IS the brand gradient — no solid
    // override, so it carries the primary colour.
    expect(button.backgroundColor, isNull);
  });

  group('every kiosk button runs at kiosk scale', () {
    testWidgets('the primary and the outline both carry the kiosk tokens, '
        'never the admin defaults', (tester) async {
      await pumpHome(tester);

      final primary = tester.widget<AppPrimaryButton>(
        find.byType(AppPrimaryButton),
      );
      expect(primary.textStyle, DesignConstants.kioskButtonPrimaryLabel);
      expect(primary.padding, DesignConstants.kioskButtonPrimaryPadding);
      expect(primary.textStyle?.fontSize, 19);

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
