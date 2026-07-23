import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_state.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_home_screen.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockRewardsRepository extends Mock implements RewardsRepository {}

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
    cubit = KioskFlowCubit(
      membersRepository: _MockMembersListRepository(),
      scheduleRepository: _MockScheduleRepository(),
      memberRepository: _MockMemberRepository(),
      rewardsRepository: rewards,
      session: session,
      gymId: 'gym-1',
    );
  });

  tearDown(() => cubit.close());

  Future<void> pumpHome(WidgetTester tester) async {
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
}
