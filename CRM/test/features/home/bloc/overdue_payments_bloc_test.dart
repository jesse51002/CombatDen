import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/home/bloc/overdue_payments_bloc.dart';
import 'package:crm/features/home/bloc/overdue_payments_event.dart';
import 'package:crm/features/home/bloc/overdue_payments_state.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _FakeCrmMembersListRequest extends Fake
    implements CrmMembersListRequest {}

void main() {
  late _MockMembersListRepository repository;
  const gymId = 'gym-1';

  setUpAll(() {
    registerFallbackValue(_FakeCrmMembersListRequest());
  });

  setUp(() {
    repository = _MockMembersListRepository();
  });

  OverdueViewRow row(String id, int daysLate) => OverdueViewRow(
        memberId: id,
        name: 'Member $id',
        membershipText: 'Gold',
        daysLate: daysLate,
      );

  const counts = MembersListTotalCounts(
    active: 10,
    trial: 2,
    frozen: 1,
    overdue: 2,
  );

  CrmMembersListResponse response(List<MemberRow> data) =>
      CrmMembersListResponse(
        view: MembersListView.overdue,
        filters: const MembersListFilters(),
        data: data,
      );

  group('OverduePaymentsBloc', () {
    blocTest<OverduePaymentsBloc, OverduePaymentsState>(
      'emits [loading, loaded] with overdue rows and count',
      setUp: () {
        when(() => repository.getTotalCounts(any()))
            .thenAnswer((_) async => counts);
        when(() => repository.getMembersList(any())).thenAnswer(
          (_) async => response([row('1', 5), row('2', 12)]),
        );
      },
      build: () => OverduePaymentsBloc(repository: repository),
      act: (bloc) =>
          bloc.add(const OverduePaymentsLoadRequested(gymId)),
      expect: () => [
        const OverduePaymentsLoading(),
        OverduePaymentsLoaded(
          rows: [row('1', 5), row('2', 12)],
          overdueCount: 2,
        ),
      ],
      verify: (_) {
        // A short page (< default page size) stops paging after one call.
        verify(() => repository.getMembersList(any())).called(1);
      },
    );

    blocTest<OverduePaymentsBloc, OverduePaymentsState>(
      'emits [loading, empty-loaded] when nobody is overdue',
      setUp: () {
        when(() => repository.getTotalCounts(any())).thenAnswer(
          (_) async => const MembersListTotalCounts(
            active: 10,
            trial: 0,
            frozen: 0,
            overdue: 0,
          ),
        );
        when(() => repository.getMembersList(any()))
            .thenAnswer((_) async => response(const []));
      },
      build: () => OverduePaymentsBloc(repository: repository),
      act: (bloc) =>
          bloc.add(const OverduePaymentsLoadRequested(gymId)),
      expect: () => const [
        OverduePaymentsLoading(),
        OverduePaymentsLoaded(rows: [], overdueCount: 0),
      ],
    );

    blocTest<OverduePaymentsBloc, OverduePaymentsState>(
      'emits [loading, error] when the repository throws',
      setUp: () {
        when(() => repository.getTotalCounts(any()))
            .thenThrow(Exception('boom'));
      },
      build: () => OverduePaymentsBloc(repository: repository),
      act: (bloc) =>
          bloc.add(const OverduePaymentsLoadRequested(gymId)),
      expect: () => [
        const OverduePaymentsLoading(),
        isA<OverduePaymentsError>(),
      ],
    );
  });
}
