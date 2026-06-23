import 'package:bloc_test/bloc_test.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

/// RemoveAuthorizationRequested must thread the EXACT (payee, payer) pair to
/// the repository — the backend cancel is pair-scoped, so a swapped or wrong
/// id would cancel the wrong member's memberships. This guards the bloc's
/// id threading (the section decides which is payee vs payer).
void main() {
  const viewedId = 'viewed-1';
  const otherId = 'other-1';
  const gymId = 'gym-1';

  MemberDetailResponse buildMember() => const MemberDetailResponse(
        memberId: viewedId,
        gymId: gymId,
        firstName: 'Pat',
        lastName: 'Lee',
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

  setUp(() {
    repo = MockMemberRepository();
    when(() => repo.getMemberDetail(any()))
        .thenAnswer((_) async => buildMember());
    when(() => repo.removeAuthorization(any(), any()))
        .thenAnswer((_) async {});
  });

  blocTest<MemberDetailBloc, MemberDetailState>(
    'remove_authorization passes the exact (payee, payer) pair through',
    build: () => MemberDetailBloc(repository: repo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const RemoveAuthorizationRequested(
        memberId: viewedId,
        payerMemberId: otherId,
      ),
    ),
    verify: (_) {
      verify(() => repo.removeAuthorization(viewedId, otherId)).called(1);
    },
  );

  blocTest<MemberDetailBloc, MemberDetailState>(
    'remove_authorization refetches member detail after the mutation',
    build: () => MemberDetailBloc(repository: repo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const RemoveAuthorizationRequested(
        memberId: otherId,
        payerMemberId: viewedId,
      ),
    ),
    verify: (_) {
      verify(() => repo.removeAuthorization(otherId, viewedId)).called(1);
      verify(() => repo.getMemberDetail(any())).called(1);
    },
  );
}
