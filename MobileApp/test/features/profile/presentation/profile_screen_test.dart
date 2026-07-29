import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/profile/data/models/billing_personal_info.dart';
import 'package:mobile_app/features/profile/data/models/billing_rank.dart';
import 'package:mobile_app/features/profile/data/models/billing_retention.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_summary_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/streak_week/profile_streak_week.dart';
import 'package:mobile_app/features/profile/presentation/widgets/streak_week/streak_facts.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_day_badge.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/sparkle_hero/sparkle_hero.dart';

class _MockProfileBloc extends MockBloc<MemberProfileEvent, MemberProfileState>
    implements MemberProfileBloc {}

const BillingRank _rank = BillingRank(
  rankId: 'r1',
  name: 'Blue Belt',
  classesToNextMajor: 50,
  classesTillNextStep: 25,
  classesSinceRank: 10,
);

MemberProfile _profile({
  int streak = 3,
  BillingRank? rank,
  List<int> week = const [],
  String? lastClass,
}) =>
    MemberProfile(
      memberId: 'm1',
      gymId: 'g1',
      firstName: 'Jane',
      lastName: 'Doe',
      personalInfo: const BillingPersonalInfo(),
      rank: rank,
      retention: BillingRetention(
        classStreakWeeks: streak,
        pointsBalance: 120,
        videosWatched: 0,
        lastClass: lastClass,
        currentWeekAttendedWeekdays: week,
      ),
    );

Future<void> _selectGym({required bool rankEnabled}) => selectedMember.select(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Global MMA',
      firstName: 'Jane',
      lastName: 'Doe',
      gymRankEnabled: rankEnabled,
      // Keep the nav at four tabs so the rank branch is the only variable.
      gymHasRewards: true,
      gymHasVideos: true,
    );

Widget _host(MemberProfileBloc bloc) => MaterialApp(
      home: BlocProvider<MemberProfileBloc>.value(
        value: bloc,
        child: const ProfileScreen(),
      ),
    );

/// Pump the profile with [profile] loaded. `pump` (not `pumpAndSettle`) — the
/// entrance animations are one-shot but the level-up carousel's future never
/// resolves in a widget test.
Future<_MockProfileBloc> _pumpProfile(
  WidgetTester tester,
  MemberProfile profile,
) async {
  final bloc = _MockProfileBloc();
  whenListen(
    bloc,
    const Stream<MemberProfileState>.empty(),
    initialState: MemberProfileState(
      status: MemberProfileStatus.loaded,
      profile: profile,
    ),
  );
  await tester.pumpWidget(_host(bloc));
  await tester.pump(const Duration(seconds: 2));
  return bloc;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // The rank-enabled branch constructs a real ApiClient (its RankProgressBloc
    // is screen-scoped), which reads API_BASE_URL at construction. The request
    // it fires never leaves the test — the bloc catches and shows its error
    // state — but the URL has to resolve.
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000');
  });

  tearDown(() => selectedMember.reset());

  group('ProfileScreen branches on the GYM flag, not on rank == null', () {
    testWidgets('a rank-enabled gym keeps the rank block', (tester) async {
      await _selectGym(rankEnabled: true);
      await _pumpProfile(tester, _profile(rank: _rank));

      expect(find.byType(RankSummarySection), findsOneWidget);
      expect(find.byType(NextRankSection), findsOneWidget);
      // The rank-less shape is NOT built.
      expect(find.byType(ProfileStreakWeek), findsNothing);
      expect(find.byType(StreakFacts), findsNothing);
    });

    testWidgets(
        'a rank-enabled gym with an UNGRADED member keeps the rank shape',
        (tester) async {
      await _selectGym(rankEnabled: true);
      await _pumpProfile(tester, _profile());

      // No rank to draw, but this member still belongs on the rank page —
      // the week strip / facts are the rank-OFF shape and must not appear.
      expect(find.byType(RankSummarySection), findsNothing);
      expect(find.byType(NextRankSection), findsNothing);
      expect(find.byType(ProfileStreakWeek), findsNothing);
      expect(find.byType(StreakFacts), findsNothing);
    });

    testWidgets('a rank-OFF gym shows the streak page instead',
        (tester) async {
      await _selectGym(rankEnabled: false);
      await _pumpProfile(tester, _profile(week: const [1, 3]));

      expect(find.byType(RankSummarySection), findsNothing);
      expect(find.byType(NextRankSection), findsNothing);
      expect(find.byType(SparkleHero), findsOneWidget);
      expect(find.byType(ProfileStreakWeek), findsOneWidget);
      expect(find.byType(StreakFacts), findsOneWidget);
    });
  });

  group('the week strip maps Sunday-first indices onto the right badges', () {
    testWidgets('0 = Sunday … 6 = Saturday', (tester) async {
      await _selectGym(rankEnabled: false);
      // Sunday, Wednesday, Saturday.
      await _pumpProfile(tester, _profile(week: const [0, 3, 6]));

      final badges = tester
          .widgetList<StreakDayBadge>(find.byType(StreakDayBadge))
          .toList(growable: false);

      expect(badges, hasLength(7));
      expect(
        badges.map((b) => b.day.completed),
        [true, false, false, true, false, false, true],
      );
      expect(badges.map((b) => b.day.label), ['S', 'M', 'T', 'W', 'T', 'F', 'S']);
    });

    testWidgets('an empty week draws seven open days, not an empty row',
        (tester) async {
      await _selectGym(rankEnabled: false);
      await _pumpProfile(tester, _profile(week: const []));

      final badges = tester
          .widgetList<StreakDayBadge>(find.byType(StreakDayBadge))
          .toList(growable: false);

      expect(badges, hasLength(7));
      expect(badges.map((b) => b.day.completed), everyElement(isFalse));
    });
  });

  group('the facts row reads the live retention', () {
    testWidgets('counts this week and names the last class weekday',
        (tester) async {
      await _selectGym(rankEnabled: false);
      await _pumpProfile(
        tester,
        // 2026-07-22 is a Wednesday.
        _profile(week: const [1, 3], lastClass: '2026-07-22T18:00:00'),
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.text('Classes this week'), findsOneWidget);
      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('Last class'), findsOneWidget);
    });

    test('a member who has never trained gets an em dash, not a crash', () {
      expect(lastClassWeekday(null), '—');
      expect(
        lastClassWeekday(
          const BillingRetention(
            classStreakWeeks: 0,
            pointsBalance: 0,
            videosWatched: 0,
          ),
        ),
        '—',
      );
      expect(
        lastClassWeekday(
          const BillingRetention(
            classStreakWeeks: 0,
            pointsBalance: 0,
            videosWatched: 0,
            lastClass: 'not-a-date',
          ),
        ),
        '—',
      );
    });
  });

  group('the ZERO-streak state celebrates nothing it has not earned', () {
    testWidgets('names the goal, kills the sparkles, offers the one action',
        (tester) async {
      await _selectGym(rankEnabled: false);
      await _pumpProfile(tester, _profile(streak: 0));

      final hero = tester.widget<SparkleHero>(find.byType(SparkleHero));
      expect(hero.top, 'START YOUR');
      expect(hero.accent, 'STREAK');
      expect(hero.bottom, 'BOOK A CLASS');
      // The sparkles are the EARNED part.
      expect(hero.showSparkles, isFalse);
      expect(find.text('0 WEEK'), findsNothing);

      // The facts row gives way to the action that starts a streak.
      expect(find.byType(StreakFacts), findsNothing);
      expect(find.text('Book a class'), findsOneWidget);
      expect(find.byType(AppPrimaryButton), findsOneWidget);

      // The strip still draws the goal's shape.
      expect(find.byType(StreakDayBadge), findsNWidgets(7));
    });

    testWidgets('a streak turns the hero and the facts back on',
        (tester) async {
      await _selectGym(rankEnabled: false);
      await _pumpProfile(tester, _profile(streak: 4, week: const [2]));

      final hero = tester.widget<SparkleHero>(find.byType(SparkleHero));
      expect(hero.top, 'YOU HAVE A');
      expect(hero.accent, '4 WEEK');
      expect(hero.showSparkles, isTrue);
      expect(find.byType(StreakFacts), findsOneWidget);
      expect(find.text('Book a class'), findsNothing);
    });

    testWidgets('an UNLOADED profile is not treated as zero', (tester) async {
      await _selectGym(rankEnabled: false);
      final bloc = _MockProfileBloc();
      whenListen(
        bloc,
        const Stream<MemberProfileState>.empty(),
        initialState: const MemberProfileState(
          status: MemberProfileStatus.loading,
        ),
      );
      await tester.pumpWidget(_host(bloc));
      await tester.pump(const Duration(seconds: 2));

      // Telling a member with a twelve-week streak to "start" one because
      // their fetch hasn't landed is worse than a dash.
      final hero = tester.widget<SparkleHero>(find.byType(SparkleHero));
      expect(hero.top, 'YOU HAVE A');
      expect(find.text('Book a class'), findsNothing);
      expect(find.byType(StreakFacts), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StreakFacts),
          matching: find.text('—'),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('a RANK-enabled gym keeps the count hero at zero',
        (tester) async {
      await _selectGym(rankEnabled: true);
      await _pumpProfile(tester, _profile(streak: 0, rank: _rank));

      final hero = tester.widget<SparkleHero>(find.byType(SparkleHero));
      expect(hero.top, 'YOU HAVE A');
      expect(hero.accent, '0 WEEK');
      expect(hero.showSparkles, isTrue);
    });
  });
}
