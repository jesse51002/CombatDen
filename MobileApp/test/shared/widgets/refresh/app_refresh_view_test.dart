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
import 'package:mobile_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:mobile_app/shared/widgets/refresh/app_refresh_view.dart';

class _MockProfileBloc extends MockBloc<MemberProfileEvent, MemberProfileState>
    implements MemberProfileBloc {}

/// The gesture a member makes: a slow drag DOWN from near the top, past the
/// indicator's trigger distance.
Future<void> _pullDown(WidgetTester tester, Finder scrollable) async {
  await tester.fling(scrollable, const Offset(0, 320), 1000);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000');
  });

  tearDown(() => selectedMember.reset());

  group('a page SHORTER than the viewport still accepts the pull', () {
    testWidgets('a near-empty scroll view — the empty catalog / empty feed',
        (tester) async {
      var pulls = 0;

      await tester.pumpWidget(_host(
        AppRefreshView(
          onRefresh: () async => pulls++,
          child: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            child: SizedBox(height: 40, child: Text('No rewards yet')),
          ),
        ),
      ));
      await _pullDown(tester, find.byType(SingleChildScrollView));

      expect(pulls, 1);
    });

    testWidgets('a viewport-sized CustomScrollView — the rank-less profile',
        (tester) async {
      var pulls = 0;

      await tester.pumpWidget(_host(
        AppRefreshView(
          onRefresh: () async => pulls++,
          child: const CustomScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Streak')),
              ),
            ],
          ),
        ),
      ));
      await _pullDown(tester, find.byType(CustomScrollView));

      expect(pulls, 1);
    });

    testWidgets('WITHOUT always-scrollable physics the same page refuses it',
        (tester) async {
      // The regression this guards: a short page silently swallowing the pull.
      var pulls = 0;

      await tester.pumpWidget(_host(
        AppRefreshView(
          onRefresh: () async => pulls++,
          child: const SingleChildScrollView(
            child: SizedBox(height: 40, child: Text('No rewards yet')),
          ),
        ),
      ));
      await _pullDown(tester, find.byType(SingleChildScrollView));

      expect(pulls, 0);
    });
  });

  group('the real tab bodies are wired for it', () {
    testWidgets('the rank-LESS profile is pullable — the shape with no '
        'overscroll of its own', (tester) async {
      await selectedMember.select(
        memberId: 'm1',
        gymId: 'g1',
        gymName: 'Global MMA',
        firstName: 'Jane',
        lastName: 'Doe',
        gymRankEnabled: false,
      );
      final bloc = _MockProfileBloc();
      whenListen(
        bloc,
        const Stream<MemberProfileState>.empty(),
        initialState: const MemberProfileState(
          status: MemberProfileStatus.loading,
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: BlocProvider<MemberProfileBloc>.value(
          value: bloc,
          child: const ProfileScreen(),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(AppRefreshView), findsOneWidget);
      final scroll = tester.widget<CustomScrollView>(
        find.descendant(
          of: find.byType(AppRefreshView),
          matching: find.byType(CustomScrollView),
        ),
      );
      expect(scroll.physics, isA<AlwaysScrollableScrollPhysics>());
    });
  });
}
