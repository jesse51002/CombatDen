import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:mobile_app/features/profile/data/models/member_promotion.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/presentation/screens/promotion_screen.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';
import 'package:mobile_app/shared/widgets/rank/rank_belt_image.dart';

class _MockProfileBloc extends MockBloc<MemberProfileEvent, MemberProfileState>
    implements MemberProfileBloc {}

const BillingRank _rank = BillingRank(
  rankId: 'r1',
  name: 'Purple Belt',
  subLabel: '1 Stripe',
  imageUrl: 'https://cdn.test/current.png',
  classesToNextMajor: 50,
  classesTillNextStep: 25,
);

MemberProfile _profile({MemberPromotion? promotion, BillingRank? rank}) =>
    MemberProfile(
      memberId: 'm1',
      gymId: 'g1',
      firstName: 'Jane',
      lastName: 'Doe',
      personalInfo: const BillingPersonalInfo(),
      retention: const BillingRetention(
        classStreakWeeks: 2,
        pointsBalance: 120,
        videosWatched: 0,
      ),
      rank: rank,
      latestPromotion: promotion,
    );

MemberPromotion _promotion({
  String activityId = 'act-1',
  String newRankName = 'Purple Belt',
  String newImageUrl = 'https://cdn.test/purple.png',
}) =>
    MemberPromotion(
      activityId: activityId,
      promotedAt: DateTime.utc(2026, 7, 25, 12),
      oldRankName: 'Blue Belt · 2 Stripes',
      newRankName: newRankName,
      oldImageUrl: 'https://cdn.test/blue.png',
      newImageUrl: newImageUrl,
    );

Future<void> _selectGym({bool rankEnabled = true}) => selectedMember.select(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Global MMA',
      firstName: 'Jane',
      lastName: 'Doe',
      gymRankEnabled: rankEnabled,
    );

/// Records the route names the card navigates to. BOTH hooks: a card hands off
/// with `pushReplacementNamed` (a REPLACE) and ends the flow with
/// `pushNamedAndRemoveUntil` (a PUSH). The screen's own initial route is
/// recorded too, so assertions read `.last` or filter.
class _RecordingObserver extends NavigatorObserver {
  final List<String> pushed = <String>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) pushed.add(name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final name = newRoute?.settings.name;
    if (name != null) pushed.add(name);
  }
}

void _phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Mounts the screen under a mocked profile bloc whose stream the caller can
/// drive, so a silent refresh landing mid-animation is reproducible.
Future<_RecordingObserver> _pumpScreen(
  WidgetTester tester, {
  required MemberProfileState initial,
  Stream<MemberProfileState>? updates,
  CelebrationData data = const CelebrationData(promoted: true),
}) async {
  _phoneSurface(tester);
  final observer = _RecordingObserver();
  final bloc = _MockProfileBloc();
  whenListen(
    bloc,
    updates ?? const Stream<MemberProfileState>.empty(),
    initialState: initial,
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [observer],
      initialRoute: AppRoutes.promotion,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => settings.name == AppRoutes.promotion
            ? BlocProvider<MemberProfileBloc>.value(
                value: bloc,
                child: const PromotionScreen(),
              )
            : const SizedBox.shrink(),
      ),
      onGenerateInitialRoutes: (name) => [
        MaterialPageRoute<void>(
          settings: RouteSettings(name: name, arguments: data),
          builder: (_) => BlocProvider<MemberProfileBloc>.value(
            value: bloc,
            child: const PromotionScreen(),
          ),
        ),
      ],
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
  return observer;
}

final Finder _belts = find.byType(RankBeltImage);

PostClassScaffold _scaffold(WidgetTester tester) =>
    tester.widget<PostClassScaffold>(find.byType(PostClassScaffold));

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => selectedMember.reset());

  testWidgets('a promotion with no class behind it ends the flow on Done',
      (tester) async {
    await _selectGym();
    await _pumpScreen(
      tester,
      initial: MemberProfileState(
        status: MemberProfileStatus.loaded,
        profile: _profile(promotion: _promotion(), rank: _rank),
      ),
    );

    // The one card pending, so the CTA is read from the flow and says Done.
    expect(_scaffold(tester).ctaLabel, 'Done');
    expect(_belts, findsNWidgets(2));

    await tester.pumpAndSettle();
    expect(find.text("YOU'VE BEEN PROMOTED"), findsOneWidget);
    // The slot is measured through the REAL scaffold's body area, not just a
    // bare Scaffold — if that measurement failed the belt would never land.
    final landed = tester.getSize(_belts.first);
    expect(landed.width, closeTo(154, 0.01));
    expect(landed.height, closeTo(100, 0.01));
  });

  testWidgets('with a class pending it hands off to the streak card',
      (tester) async {
    await _selectGym();
    final nav = await _pumpScreen(
      tester,
      initial: MemberProfileState(
        status: MemberProfileStatus.loaded,
        profile: _profile(promotion: _promotion(), rank: _rank),
      ),
      data: CelebrationData(
        occurredAt: DateTime.utc(2026, 7, 23, 18),
        promoted: true,
      ),
    );

    expect(_scaffold(tester).ctaLabel, 'Continue');
    _scaffold(tester).onCtaPressed();
    await tester.pumpAndSettle();

    expect(nav.pushed.last, AppRoutes.postClassStreak);
  });

  group('the self-skip is the deep-link backstop', () {
    testWidgets('no promotion and no rank pops home exactly ONCE',
        (tester) async {
      await _selectGym();
      final controller = StreamController<MemberProfileState>();
      addTearDown(controller.close);
      final profile = _profile();
      final nav = await _pumpScreen(
        tester,
        initial: MemberProfileState(
          status: MemberProfileStatus.loaded,
          profile: profile,
        ),
        updates: controller.stream,
      );

      // A rebuild must not schedule the pop a second time.
      controller.add(
        MemberProfileState(
          status: MemberProfileStatus.loaded,
          profile: _profile(),
        ),
      );
      await tester.pumpAndSettle();

      expect(nav.pushed.where((r) => r == AppRoutes.home), hasLength(1));
    });

    testWidgets('a gym with ranks OFF never renders the card', (tester) async {
      await _selectGym(rankEnabled: false);
      final nav = await _pumpScreen(
        tester,
        initial: MemberProfileState(
          status: MemberProfileStatus.loaded,
          profile: _profile(promotion: _promotion(), rank: _rank),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PostClassScaffold), findsNothing);
      expect(nav.pushed.last, AppRoutes.home);
    });

    testWidgets('a promotion with no NAME cannot render, so it pops home',
        (tester) async {
      await _selectGym();
      final nav = await _pumpScreen(
        tester,
        initial: MemberProfileState(
          status: MemberProfileStatus.loaded,
          profile: _profile(
            promotion: MemberPromotion(
              activityId: 'act-1',
              promotedAt: DateTime.utc(2026, 7, 25, 12),
              oldRankName: 'Blue Belt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(nav.pushed.last, AppRoutes.home);
    });
  });

  testWidgets('a refresh mid-animation cannot swap the belts under the member',
      (tester) async {
    await _selectGym();
    final controller = StreamController<MemberProfileState>();
    addTearDown(controller.close);
    await _pumpScreen(
      tester,
      initial: MemberProfileState(
        status: MemberProfileStatus.loaded,
        profile: _profile(promotion: _promotion(), rank: _rank),
      ),
      updates: controller.stream,
    );

    List<String?> beltUrls() =>
        tester.widgetList<RankBeltImage>(_belts).map((b) => b.imageUrl).toList();
    final before = beltUrls();
    expect(before, ['https://cdn.test/blue.png', 'https://cdn.test/purple.png']);

    // Staff promote again while the animation is still running.
    controller.add(
      MemberProfileState(
        status: MemberProfileStatus.loaded,
        profile: _profile(
          promotion: _promotion(
            activityId: 'act-2',
            newRankName: 'Brown Belt',
            newImageUrl: 'https://cdn.test/brown.png',
          ),
          rank: _rank,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // The promotion was captured on first build: the belts, and the words,
    // are the ones the member started watching.
    expect(beltUrls(), before);
    await tester.pumpAndSettle();
    expect(find.text('Purple Belt'), findsOneWidget);
    expect(find.text('Brown Belt'), findsNothing);
  });

  testWidgets('the DEBUG row previews the first-assignment state truthfully',
      (tester) async {
    // Reached by the identity sheet's `Belt promotion` row on a member whose
    // profile carries no promotion: rather than doing nothing or fabricating a
    // belt, it shows their REAL current rank as an arrival.
    await _selectGym();
    await _pumpScreen(
      tester,
      initial: MemberProfileState(
        status: MemberProfileStatus.loaded,
        profile: _profile(rank: _rank),
      ),
    );

    expect(_belts, findsOneWidget);
    expect(
      tester.widget<RankBeltImage>(_belts).imageUrl,
      'https://cdn.test/current.png',
    );

    await tester.pumpAndSettle();
    expect(find.text('YOUR FIRST RANK'), findsOneWidget);
    expect(find.text('Purple Belt · 1 Stripe'), findsOneWidget);
  });

  testWidgets('a profile still loading holds rather than flashing', (tester) async {
    await _selectGym();
    final nav = await _pumpScreen(
      tester,
      initial: const MemberProfileState(status: MemberProfileStatus.loading),
    );

    expect(find.byType(PostClassScaffold), findsNothing);
    // And it does NOT decide there is nothing to show and bounce home.
    expect(nav.pushed, isNot(contains(AppRoutes.home)));
  });
}
