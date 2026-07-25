import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/members_list/bloc/members_list_bloc.dart';
import 'package:crm/features/members_list/bloc/members_list_event.dart';
import 'package:crm/features/members_list/bloc/members_list_state.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/models/rank_ladder.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';

class _MockListRepo extends Mock implements MembersListRepository {}

class _MockMembershipsRepo extends Mock
    implements MembershipsRepository {}

class _MockRanksRepo extends Mock implements RanksRepository {}

class _FakeRequest extends Fake implements CrmMembersListRequest {}

const _counts = MembersListTotalCounts(
  active: 3,
  trial: 1,
  frozen: 0,
  overdue: 2,
);

final _plan = MembershipPlanResponse(
  planId: 'plan-gold',
  gymId: 'gym-1',
  planName: 'Gold',
  imageUrl: 'https://cdn.combatden.net/membership/presets/activity-01.jpg',
  planType: PlanType.recurring,
  isPublic: true,
  createdAt: DateTime(2026, 1, 1),
);

/// Mirrors the real backend: it echoes the request's view + filters
/// straight back (no reconciliation), so the bloc's kept-filter
/// behavior is exercised end to end.
CrmMembersListResponse _echo(Invocation inv) {
  final req =
      inv.positionalArguments.first as CrmMembersListRequest;
  return CrmMembersListResponse(
    view: req.view,
    filters: req.filters,
    data: const [],
  );
}

void main() {
  late _MockListRepo listRepo;
  late _MockMembershipsRepo membershipsRepo;
  late _MockRanksRepo ranksRepo;

  setUpAll(() => registerFallbackValue(_FakeRequest()));

  setUp(() {
    listRepo = _MockListRepo();
    membershipsRepo = _MockMembershipsRepo();
    ranksRepo = _MockRanksRepo();
    when(() => listRepo.getMembersList(any()))
        .thenAnswer((inv) async => _echo(inv));
    when(() => listRepo.getTotalCounts(any()))
        .thenAnswer((_) async => _counts);
    when(() => membershipsRepo.listPlans(any()))
        .thenAnswer((_) async => [_plan]);
    when(() => ranksRepo.listRanks(any())).thenAnswer(
      (_) async =>
          const RankLadder(ranks: [], subRankType: RankSubType.stripes),
    );
  });

  MembersListBloc build() => MembersListBloc(
        repository: listRepo,
        membershipsRepository: membershipsRepo,
        ranksRepository: ranksRepo,
      );

  MembersListLoaded loaded({
    MembersListView view = MembersListView.all,
    MembersListFilters filters = const MembersListFilters(),
  }) {
    return MembersListLoaded(
      gymId: 'gym-1',
      activeView: view,
      filters: filters,
      plans: [_plan],
      allRows: const [],
      displayedRows: const [],
      totalCounts: _counts,
    );
  }

  group('MembersListBloc', () {
    blocTest<MembersListBloc, MembersListState>(
      'init loads the list, counts, and plans',
      build: build,
      act: (b) =>
          b.add(const MembersListInitRequested('gym-1')),
      expect: () => [
        const MembersListLoading(),
        isA<MembersListLoaded>()
            .having((s) => s.activeView, 'activeView',
                MembersListView.all)
            .having((s) => s.plans, 'plans', [_plan])
            .having((s) => s.totalCounts, 'totalCounts', _counts),
      ],
    );

    blocTest<MembersListBloc, MembersListState>(
      'a failed plan load degrades to empty plans; '
      'the list still loads',
      build: () {
        when(() => membershipsRepo.listPlans(any()))
            .thenThrow(Exception('boom'));
        return build();
      },
      act: (b) =>
          b.add(const MembersListInitRequested('gym-1')),
      expect: () => [
        const MembersListLoading(),
        isA<MembersListLoaded>()
            .having((s) => s.plans, 'plans', isEmpty),
      ],
    );

    blocTest<MembersListBloc, MembersListState>(
      'switching the view KEEPS the active filters '
      '(no smart reconciliation)',
      build: build,
      seed: () => loaded(
        view: MembersListView.all,
        filters: const MembersListFilters(
          membershipStatus: [MembershipStatus.active],
        ),
      ),
      act: (b) => b.add(
        const MembersListViewChanged(MembersListView.trial),
      ),
      expect: () => [
        const MembersListLoading(),
        isA<MembersListLoaded>()
            .having((s) => s.activeView, 'activeView',
                MembersListView.trial)
            .having((s) => s.filters.membershipStatus,
                'status kept', [MembershipStatus.active]),
      ],
    );

    blocTest<MembersListBloc, MembersListState>(
      'applying filters KEEPS the current view '
      '(no smart switch)',
      build: build,
      seed: () => loaded(view: MembersListView.trial),
      act: (b) => b.add(
        const MembersListFiltersApplied(
          MembersListFilters(planIds: ['plan-gold']),
        ),
      ),
      expect: () => [
        const MembersListLoading(),
        isA<MembersListLoaded>()
            .having((s) => s.activeView, 'activeView',
                MembersListView.trial)
            .having((s) => s.filters.planIds, 'planIds',
                ['plan-gold']),
      ],
    );

    blocTest<MembersListBloc, MembersListState>(
      'switching to Incomplete asks the backend for that view',
      build: build,
      seed: () => loaded(view: MembersListView.all),
      act: (b) => b.add(
        const MembersListViewChanged(
          MembersListView.incomplete,
        ),
      ),
      expect: () => [
        const MembersListLoading(),
        isA<MembersListLoaded>().having(
            (s) => s.activeView, 'activeView',
            MembersListView.incomplete),
      ],
      verify: (_) {
        final req = verify(
          () => listRepo.getMembersList(captureAny()),
        ).captured.last as CrmMembersListRequest;
        expect(req.view, MembersListView.incomplete);
        expect(req.gymId, 'gym-1');
      },
    );

    blocTest<MembersListBloc, MembersListState>(
      'removing a plan filter drops just that plan id',
      build: build,
      seed: () => loaded(
        filters: const MembersListFilters(
          planIds: ['plan-gold', 'plan-silver'],
        ),
      ),
      act: (b) => b.add(
        const MembersListPlanFilterRemoved('plan-gold'),
      ),
      expect: () => [
        const MembersListLoading(),
        isA<MembersListLoaded>().having(
            (s) => s.filters.planIds, 'planIds', ['plan-silver']),
      ],
    );
  });
}
