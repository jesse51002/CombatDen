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
import 'package:mobile_app/features/stats/presentation/screens/points_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/rewards_card_screen.dart';
import 'package:mobile_app/features/stats/presentation/screens/streak_screen.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

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

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000');
  });

  tearDown(() => selectedMember.reset());

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
  });

  group('the LAST card terminates cleanly', () {
    testWidgets('rewards is the last card at a rank-OFF gym: Done → home',
        (tester) async {
      await _selectGym(rankEnabled: false, hasRewards: true);
      final nav = await _pumpCard(
        tester,
        RewardsCardScreen(repository: _PendingRewardsRepo()),
        rank: _rank,
      );

      // Not "Continue" into a rank screen that would flash an empty frame.
      expect(_cta(tester).ctaLabel, 'Done');
      _cta(tester).onCtaPressed();
      await tester.pump();

      expect(nav.pushed.last, AppRoutes.home);
      expect(nav.pushed, isNot(contains(AppRoutes.postClassRank)));
    });

    testWidgets('rewards is also the last card for an UNGRADED member',
        (tester) async {
      await _selectGym(rankEnabled: true, hasRewards: true);
      await _pumpCard(
        tester,
        RewardsCardScreen(repository: _PendingRewardsRepo()),
      );

      expect(_cta(tester).ctaLabel, 'Done');
    });

    testWidgets('at the emptiest gym, points is the last card: Done → home',
        (tester) async {
      await _selectGym(rankEnabled: false, hasRewards: false);
      final nav = await _pumpCard(tester, const PointsScreen());

      expect(_cta(tester).ctaLabel, 'Done');
      _cta(tester).onCtaPressed();
      await tester.pumpAndSettle();

      expect(nav.pushed.last, AppRoutes.home);
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
}
