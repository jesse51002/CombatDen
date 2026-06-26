import 'package:bloc_test/bloc_test.dart';
import 'package:crm/features/member_details/bloc/invoice_poller.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_upgrade_request.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

/// No real timers (upgrade triggers the invoice poll; the schedule itself
/// is proven in `invoice_poller_test.dart`).
class FakeInvoicePoller extends InvoicePoller {
  @override
  void start(void Function() onTick) {}
  @override
  void cancel() {}
}

void main() {
  const memberId = 'member-1';
  const gymId = 'gym-1';

  MemberDetailResponse buildMember() => MemberDetailResponse(
        memberId: memberId,
        gymId: gymId,
        firstName: 'Kid',
        lastName: 'Smith',
        membershipOverview: '1 membership',
        totalMonthlyRecurringPrice: 5000,
        totalMembershipCount: 1,
        personalInfo: const PersonalInfo(),
        retention: const Retention(
          classStreakWeeks: 0,
          pointsBalance: 0,
          videosWatched: 0,
        ),
      );

  MemberDetailLoaded seedState() => MemberDetailLoaded(
        member: buildMember(),
        allMembers: const [],
        filteredMembers: const [],
      );

  late MockMemberRepository repo;

  setUpAll(() {
    registerFallbackValue(
      const MemberMembershipsUpgradeRequest(
        itemId: '',
        memberId: '',
        targetPlanId: '',
        prorationBehavior: ProrationBehavior.prorateToAnchor,
        idempotencyKey: '',
      ),
    );
  });

  setUp(() {
    repo = MockMemberRepository();
    when(() => repo.getMemberDetail(any()))
        .thenAnswer((_) async => buildMember());
  });

  MemberDetailBloc build() =>
      MemberDetailBloc(repository: repo, poller: FakeInvoicePoller());

  group('upgrade channel', () {
    blocTest<MemberDetailBloc, MemberDetailState>(
      'success bumps upgradeSuccess + refreshToken (own channel)',
      setUp: () => when(() => repo.upgradeMembership(any()))
          .thenAnswer((_) async {}),
      build: build,
      seed: seedState,
      act: (bloc) => bloc.add(const UpgradeMembershipRequested(
        itemId: 'it_1',
        memberId: memberId,
        targetPlanId: 'plan-2',
      )),
      expect: () => [
        isA<MemberDetailLoaded>()
            .having((s) => s.isUpgrading, 'isUpgrading', true),
        // Success commits the token + refreshToken. The best-effort member
        // re-fetch returns an equal member, so its copyWith is deduped — the
        // success state is the last distinct emission.
        isA<MemberDetailLoaded>()
            .having((s) => s.isUpgrading, 'isUpgrading', false)
            .having((s) => s.upgradeSuccess, 'upgradeSuccess', 1)
            .having((s) => s.refreshToken, 'refreshToken', 1)
            .having((s) => s.upgradeError, 'upgradeError', isNull),
      ],
    );

    blocTest<MemberDetailBloc, MemberDetailState>(
      'error sets upgradeError, no success token, not on actionError',
      setUp: () => when(() => repo.upgradeMembership(any()))
          .thenThrow(Exception('stripe boom')),
      build: build,
      seed: seedState,
      act: (bloc) => bloc.add(const UpgradeMembershipRequested(
        itemId: 'it_1',
        memberId: memberId,
        targetPlanId: 'plan-2',
      )),
      expect: () => [
        isA<MemberDetailLoaded>()
            .having((s) => s.isUpgrading, 'isUpgrading', true),
        isA<MemberDetailLoaded>()
            .having((s) => s.isUpgrading, 'isUpgrading', false)
            .having((s) => s.upgradeError, 'upgradeError', isNotNull)
            .having((s) => s.upgradeSuccess, 'upgradeSuccess', 0)
            .having((s) => s.actionError, 'actionError', isNull),
      ],
    );
  });

  group('end channel', () {
    blocTest<MemberDetailBloc, MemberDetailState>(
      'success bumps endSuccess + refreshToken (own channel)',
      setUp: () => when(() => repo.endMembership(
            itemId: any(named: 'itemId'),
            memberId: any(named: 'memberId'),
          )).thenAnswer((_) async {}),
      build: build,
      seed: seedState,
      act: (bloc) => bloc.add(const EndMembershipRequested(
        itemId: 'it_1',
        memberId: memberId,
      )),
      expect: () => [
        isA<MemberDetailLoaded>()
            .having((s) => s.isEnding, 'isEnding', true),
        // See the upgrade success note: the equal-member re-fetch is deduped.
        isA<MemberDetailLoaded>()
            .having((s) => s.isEnding, 'isEnding', false)
            .having((s) => s.endSuccess, 'endSuccess', 1)
            .having((s) => s.refreshToken, 'refreshToken', 1)
            .having((s) => s.endError, 'endError', isNull),
      ],
    );

    blocTest<MemberDetailBloc, MemberDetailState>(
      'error sets endError, no success token',
      setUp: () => when(() => repo.endMembership(
            itemId: any(named: 'itemId'),
            memberId: any(named: 'memberId'),
          )).thenThrow(Exception('cannot end')),
      build: build,
      seed: seedState,
      act: (bloc) => bloc.add(const EndMembershipRequested(
        itemId: 'it_1',
        memberId: memberId,
      )),
      expect: () => [
        isA<MemberDetailLoaded>()
            .having((s) => s.isEnding, 'isEnding', true),
        isA<MemberDetailLoaded>()
            .having((s) => s.isEnding, 'isEnding', false)
            .having((s) => s.endError, 'endError', isNotNull)
            .having((s) => s.endSuccess, 'endSuccess', 0),
      ],
    );
  });
}
