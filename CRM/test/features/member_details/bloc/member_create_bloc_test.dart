import 'package:bloc_test/bloc_test.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/member_create_bloc.dart';
import 'package:crm/features/member_details/bloc/member_create_event.dart';
import 'package:crm/features/member_details/bloc/member_create_state.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

void main() {
  const gymId = 'gym-1';

  MembersManagementCreateRequest buildRequest({bool allow = false}) =>
      MembersManagementCreateRequest(
        gymId: gymId,
        firstName: 'Jo',
        lastName: 'Doe',
        email: 'jo@example.com',
        allowDuplicate: allow,
      );

  const match = DuplicateMemberMatch(
    memberId: 'existing-1',
    firstName: 'Jo',
    lastName: 'Doe',
    email: 'jo@example.com',
  );

  late MockMemberRepository repo;

  setUpAll(() {
    registerFallbackValue(buildRequest());
  });

  setUp(() {
    repo = MockMemberRepository();
  });

  blocTest<MemberCreateBloc, MemberCreateState>(
    'submit creates the member and emits MemberCreated',
    build: () {
      when(() => repo.createMember(any()))
          .thenAnswer((_) async => 'new-1');
      return MemberCreateBloc(repository: repo);
    },
    act: (bloc) => bloc.add(MemberCreateSubmitted(buildRequest())),
    expect: () => [
      isA<MemberCreateSubmitting>(),
      isA<MemberCreated>()
          .having((s) => s.memberId, 'memberId', 'new-1'),
    ],
  );

  blocTest<MemberCreateBloc, MemberCreateState>(
    'a duplicate gate lands on MemberCreateDuplicate with the pending request',
    build: () {
      when(() => repo.createMember(any()))
          .thenThrow(const DuplicateMemberException([match]));
      return MemberCreateBloc(repository: repo);
    },
    act: (bloc) => bloc.add(MemberCreateSubmitted(buildRequest())),
    expect: () => [
      isA<MemberCreateSubmitting>(),
      isA<MemberCreateDuplicate>()
          .having((s) => s.matches, 'matches', [match])
          .having(
            (s) => s.pendingRequest.allowDuplicate,
            'pending allowDuplicate',
            false,
          ),
    ],
  );

  blocTest<MemberCreateBloc, MemberCreateState>(
    'create-anyway re-sends the pending request with allow_duplicate true',
    build: () {
      when(() => repo.createMember(any()))
          .thenAnswer((_) async => 'forced-1');
      return MemberCreateBloc(repository: repo);
    },
    seed: () => MemberCreateDuplicate(
      matches: const [match],
      pendingRequest: buildRequest(),
    ),
    act: (bloc) => bloc.add(const MemberCreateAnywayRequested()),
    expect: () => [
      isA<MemberCreateSubmitting>(),
      isA<MemberCreated>()
          .having((s) => s.memberId, 'memberId', 'forced-1'),
    ],
    verify: (_) {
      final captured =
          verify(() => repo.createMember(captureAny())).captured;
      expect(
        (captured.last as MembersManagementCreateRequest).allowDuplicate,
        isTrue,
      );
    },
  );

  blocTest<MemberCreateBloc, MemberCreateState>(
    'use-existing emits MemberCreated without a POST',
    build: () => MemberCreateBloc(repository: repo),
    seed: () => MemberCreateDuplicate(
      matches: const [match],
      pendingRequest: buildRequest(),
    ),
    act: (bloc) => bloc.add(const MemberCreateUseExisting('existing-1')),
    expect: () => [
      isA<MemberCreated>()
          .having((s) => s.memberId, 'memberId', 'existing-1'),
    ],
    verify: (_) {
      verifyNever(() => repo.createMember(any()));
    },
  );

  blocTest<MemberCreateBloc, MemberCreateState>(
    'a 400 (no Stripe account) fails with needsStripeSetup',
    build: () {
      when(() => repo.createMember(any())).thenThrow(
        const ServerException('bad', statusCode: 400, detail: 'no account'),
      );
      return MemberCreateBloc(repository: repo);
    },
    act: (bloc) => bloc.add(MemberCreateSubmitted(buildRequest())),
    expect: () => [
      isA<MemberCreateSubmitting>(),
      isA<MemberCreateFailure>()
          .having((s) => s.needsStripeSetup, 'needsStripeSetup', true)
          .having((s) => s.message, 'message', 'no account'),
    ],
  );

  blocTest<MemberCreateBloc, MemberCreateState>(
    'a generic failure keeps needsStripeSetup false',
    build: () {
      when(() => repo.createMember(any()))
          .thenThrow(Exception('network down'));
      return MemberCreateBloc(repository: repo);
    },
    act: (bloc) => bloc.add(MemberCreateSubmitted(buildRequest())),
    expect: () => [
      isA<MemberCreateSubmitting>(),
      isA<MemberCreateFailure>()
          .having((s) => s.needsStripeSetup, 'needsStripeSetup', false),
    ],
  );
}
