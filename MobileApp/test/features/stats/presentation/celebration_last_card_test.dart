import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/profile/data/models/billing_personal_info.dart';
import 'package:mobile_app/features/profile/data/models/billing_rank.dart';
import 'package:mobile_app/features/profile/data/models/billing_retention.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/rewards/data/repositories/member_rewards_repository.dart';
import 'package:mobile_app/features/stats/data/celebration_rewards_gate.dart';
import 'package:mobile_app/features/stats/presentation/screens/points_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/rank_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/rewards_card_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/streak_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/wins_screen.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

import '../../../helpers/fake_rewards_catalog.dart';

class _MockProfileBloc extends MockBloc<MemberProfileEvent, MemberProfileState>
    implements MemberProfileBloc {}

/// A catalog fetch that never resolves — holds the rewards card on its load
/// state so the CTA under test isn't buried under the carousel. The CTA's
/// label and destination are decided before the catalog lands, which is the
/// point: the flow's shape comes from the gym flags, not the payload.
class _PendingRewardsRepo implements MemberRewardsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

const BillingRank _rank = BillingRank(
  rankId: 'r1',
  name: 'Blue Belt',
  classesToNextMajor: 50,
  classesTillNextStep: 25,
);

MemberProfile _profile({BillingRank? rank}) => MemberProfile(
      memberId: 'm1',
      gymId: 'g1',
      firstName: 'Jane',
      lastName: 'Doe',
      personalInfo: const BillingPersonalInfo(),
      rank: rank,
      retention: const BillingRetention(
        classStreakWeeks: 2,
        pointsBalance: 120,
        videosWatched: 0,
      ),
    );

Future<void> _selectGym({
  required bool rankEnabled,
  required bool hasRewards,
}) =>
    selectedMember.select(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Global MMA',
      firstName: 'Jane',
      lastName: 'Doe',
      gymRankEnabled: rankEnabled,
      gymHasRewards: hasRewards,
    );

/// Records the route names the card navigates to — a `NavigatorObserver`
/// rather than an `onGenerateRoute` hook because `MaterialApp.home` claims
/// `'/'` itself, so the home route would never reach a generator. Both hooks
/// are recorded: a card hands off with `pushReplacementNamed` (a REPLACE) and
/// ends the flow with `pushNamedAndRemoveUntil` (a PUSH).
class _RecordingObserver extends NavigatorObserver {
  final List<String?> pushed = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    pushed.add(newRoute?.settings.name);
  }
}

/// Mounts [card] under a recording navigator and the shared profile bloc.
Future<_RecordingObserver> _pumpCard(
  WidgetTester tester,
  Widget card, {
  BillingRank? rank,
}) async {
  final observer = _RecordingObserver();
  final bloc = _MockProfileBloc();
  whenListen(
    bloc,
    const Stream<MemberProfileState>.empty(),
    initialState: MemberProfileState(
      status: MemberProfileStatus.loaded,
      profile: _profile(rank: rank),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [observer],
      home: BlocProvider<MemberProfileBloc>.value(value: bloc, child: card),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pump();
  // Drop the initial mount so only what the CTA drives is asserted.
  observer.pushed.clear();
  return observer;
}

/// The card's CTA, read off the scaffold so the assertion doesn't have to wait
/// out each card's entrance animation before the button fades in.
PostClassScaffold _cta(WidgetTester tester) =>
    tester.widget<PostClassScaffold>(find.byType(PostClassScaffold));

/// Runs a card's entrance out to the end. The stagger delays and count-up
/// delays are plain timers, and `pumpAndSettle` only advances the clock while
/// a frame is scheduled — so it can return with those still pending, which
/// fails the test.
Future<void> _drainEntrance(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// Sizes the surface like a phone. The app is Android/iOS only, and the wins
/// card's trophy hero is taller than the default 800×600 test window — which
/// is shorter than any device it ships on.
void _phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000');
  });

  tearDown(() {
    selectedMember.reset();
    // The gate is a process-wide singleton; a leaked catalog would decide the
    // next test's flow.
    CelebrationRewardsGate.instance.reset();
  });

  group('the celebration chains only to cards that apply', () {
    testWidgets('points continues to the REWARDS card at a gym with rewards',
        (tester) async {
      await _selectGym(rankEnabled: true, hasRewards: true);
      final nav = await _pumpCard(tester, const PointsScreen(), rank: _rank);

      expect(_cta(tester).ctaLabel, 'Continue');
      _cta(tester).onCtaPressed();
      await tester.pumpAndSettle();

      expect(nav.pushed.last, AppRoutes.postClassRewards);
    });

    testWidgets('with no rewards, points skips straight to the RANK card',
        (tester) async {
      await _selectGym(rankEnabled: true, hasRewards: false);
      final nav = await _pumpCard(tester, const PointsScreen(), rank: _rank);

      expect(_cta(tester).ctaLabel, 'Continue');
      _cta(tester).onCtaPressed();
      await tester.pumpAndSettle();

      expect(nav.pushed.last, AppRoutes.postClassRank);
    });

    testWidgets('a catalog this member cannot reach also skips the card',
        (tester) async {
      // The gym runs rewards, but the cheapest is 5,000 and the member holds
      // 120 — nowhere near the 90% mark, so the card would only say "you can't
      // have any of this".
      await _selectGym(rankEnabled: true, hasRewards: true);
      await primeRewardsGate([5000]);
      final nav = await _pumpCard(tester, const PointsScreen(), rank: _rank);

      _cta(tester).onCtaPressed();
      await tester.pumpAndSettle();

      expect(nav.pushed.last, AppRoutes.postClassRank);
      expect(nav.pushed, isNot(contains(AppRoutes.postClassRewards)));
    });

    testWidgets('90% of the cheapest is close enough to keep the card',
        (tester) async {
      // 120 of a 133-point reward: 120 * 10 >= 133 * 9.
      await _selectGym(rankEnabled: true, hasRewards: true);
      await primeRewardsGate([133, 5000]);
      final nav = await _pumpCard(tester, const PointsScreen(), rank: _rank);

      _cta(tester).onCtaPressed();
      await tester.pumpAndSettle();

      expect(nav.pushed.last, AppRoutes.postClassRewards);
    });
  });

  group('the flow tail moved: every gym shape now CONTINUES into wins', () {
    testWidgets('an unreachable catalog sends points past rewards to wins',
        (tester) async {
      await _selectGym(rankEnabled: false, hasRewards: true);
      await primeRewardsGate([5000]);
      final nav = await _pumpCard(tester, const PointsScreen(), rank: _rank);

      expect(_cta(tester).ctaLabel, 'Continue');
      _cta(tester).onCtaPressed();
      await tester.pumpAndSettle();

      expect(nav.pushed.last, AppRoutes.postClassWins);
      expect(nav.pushed, isNot(contains(AppRoutes.postClassRewards)));
    });

    testWidgets('the RANK card reads Continue — wins now follows it',
        (tester) async {
      await _selectGym(rankEnabled: true, hasRewards: true);
      final nav = await _pumpCard(tester, const RankScreen(), rank: _rank);

      // It reads the flow rather than hardcoding a label, which is exactly why
      // appending the wins card flipped it from "Done" without touching it.
      expect(_cta(tester).ctaLabel, 'Continue');
      _cta(tester).onCtaPressed();
      await _drainEntrance(tester);

      expect(nav.pushed.last, AppRoutes.postClassWins);
    });

    testWidgets('rewards continues into wins at a rank-OFF gym',
        (tester) async {
      await _selectGym(rankEnabled: false, hasRewards: true);
      final nav = await _pumpCard(
        tester,
        RewardsCardScreen(repository: _PendingRewardsRepo()),
        rank: _rank,
      );

      expect(_cta(tester).ctaLabel, 'Continue');
      _cta(tester).onCtaPressed();
      await tester.pump();

      expect(nav.pushed.last, AppRoutes.postClassWins);
      // Still never into a rank screen that would flash an empty frame.
      expect(nav.pushed, isNot(contains(AppRoutes.postClassRank)));
    });

    testWidgets('rewards also continues for an UNGRADED member', (tester) async {
      await _selectGym(rankEnabled: true, hasRewards: true);
      await _pumpCard(
        tester,
        RewardsCardScreen(repository: _PendingRewardsRepo()),
      );

      expect(_cta(tester).ctaLabel, 'Continue');
    });

    testWidgets('at the emptiest gym, points continues into wins',
        (tester) async {
      await _selectGym(rankEnabled: false, hasRewards: false);
      final nav = await _pumpCard(tester, const PointsScreen());

      expect(_cta(tester).ctaLabel, 'Continue');
      _cta(tester).onCtaPressed();
      await tester.pumpAndSettle();

      expect(nav.pushed.last, AppRoutes.postClassWins);
    });

    testWidgets('streak still hands off to points everywhere', (tester) async {
      await _selectGym(rankEnabled: false, hasRewards: false);
      final nav = await _pumpCard(tester, const StreakScreen());

      expect(_cta(tester).ctaLabel, 'Continue');
      _cta(tester).onCtaPressed();
      await tester.pumpAndSettle();

      expect(nav.pushed.last, AppRoutes.postClassPoints);
    });
  });

  group('the WINS card closes the flow', () {
    testWidgets('its CTA is the themed book-next-class label, not "Done"',
        (tester) async {
      _phoneSurface(tester);
      await _selectGym(rankEnabled: true, hasRewards: true);
      await _pumpCard(tester, const WinsScreen(), rank: _rank);

      // The one documented exception to `celebrationCtaLabel`: the card exists
      // to nudge the next booking, so it can't end on "Done".
      expect(_cta(tester).ctaLabel, 'Book your next class');
      expect(_cta(tester).ctaLabel, isNot('Done'));

      await _drainEntrance(tester);
    });

    testWidgets('the CTA lands home, at the emptiest gym too', (tester) async {
      _phoneSurface(tester);
      await _selectGym(rankEnabled: false, hasRewards: false);
      final nav = await _pumpCard(tester, const WinsScreen());

      _cta(tester).onCtaPressed();
      await _drainEntrance(tester);

      expect(nav.pushed.last, AppRoutes.home);
    });
  });
}
