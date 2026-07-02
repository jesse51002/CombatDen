import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

class MockScheduleRepository extends Mock implements ScheduleRepository {}

class MockRanksRepository extends Mock implements RanksRepository {}

class MockMembersManagementResponse extends Mock
    implements MembersManagementResponse {}

/// A mutation captures `state` before its awaits and refreshes after.
/// Bloc processes events concurrently, so a page/search change that
/// lands during those awaits must survive the refresh — it must not be
/// clobbered by the stale pre-await snapshot.
void main() {
  const memberId = 'member-1';
  const gymId = 'gym-1';

  MemberDetailResponse buildMember() => const MemberDetailResponse(
        memberId: memberId,
        gymId: gymId,
        firstName: 'Kid',
        lastName: 'Smith',
        membershipOverview: '1 membership',
        totalMonthlyRecurringPrice: 5000,
        totalMembershipCount: 1,
        personalInfo: PersonalInfo(),
        retention: Retention(
          classStreakWeeks: 0,
          pointsBalance: 0,
          videosWatched: 0,
        ),
      );

  late MockMemberRepository repo;
  late MockScheduleRepository scheduleRepo;

  setUp(() {
    repo = MockMemberRepository();
    scheduleRepo = MockScheduleRepository();
    when(() => repo.unlinkMemberPayment(any()))
        .thenAnswer((_) async => MockMembersManagementResponse());
  });

  blocTest<MemberDetailBloc, MemberDetailState>(
    'a page change that lands mid-mutation survives the refresh',
    build: () {
      final gate = Completer<void>();
      var calls = 0;
      when(() => repo.getMemberDetail(any())).thenAnswer((_) async {
        calls++;
        // Gate the mutation's refresh so a page change can land while
        // it is in flight.
        if (calls == 1) await gate.future;
        return buildMember();
      });
      Future<void>.delayed(const Duration(milliseconds: 20))
          .then((_) => gate.complete());
      return MemberDetailBloc(repository: repo, ranksRepository: MockRanksRepository(), scheduleRepository: scheduleRepo);
    },
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ), // currentMembershipIndex 0
    act: (bloc) async {
      bloc.add(const UnlinkPaymentRequested()); // gated refresh
      await Future<void>.delayed(Duration.zero);
      bloc.add(const MembershipPageChanged(2)); // lands mid-mutation
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
    verify: (bloc) {
      final st = bloc.state as MemberDetailLoaded;
      expect(st.currentMembershipIndex, 2); // not reverted to 0
      expect(st.isMutating, false);
      expect(st.refreshToken, 1);
    },
  );
}
