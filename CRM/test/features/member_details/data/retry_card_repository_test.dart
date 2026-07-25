import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/member_memberships_retry_card_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_retry_card_status.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

/// Repository-level coverage for `retryMembershipCard`. The bank's answer is
/// the RETURN VALUE, not an exception: a collected charge is `status: paid`
/// (200) and a DECLINE is `status: declined` (207) with Stripe's reason —
/// both 2xx, so both parse here instead of throwing. Only real failures
/// throw: a 409 as `MembershipInTaskException`, a 500 as `ServerException`,
/// and a 2xx whose body is not the documented outcome shape (fail closed —
/// never imply the money moved).
void main() {
  const req = MemberMembershipsRetryCardRequest(
    itemId: 'item-a',
    memberId: 'member-1',
    idempotencyKey: 'key-1',
  );

  late MockApiClient api;
  late MemberRepository repo;

  Response<dynamic> response(Object? data, {int? statusCode}) =>
      Response<dynamic>(
        requestOptions: RequestOptions(
          path: '/api/v1/member_memberships/retry-card',
        ),
        data: data,
        statusCode: statusCode,
      );

  void stubPost(Response<dynamic> Function() build) {
    when(
      () => api.post<dynamic>(any(), data: any(named: 'data')),
    ).thenAnswer((_) async => build());
  }

  setUp(() {
    api = MockApiClient();
    repo = MemberRepository(apiClient: api);
  });

  test('200: a collected charge parses as paid', () async {
    stubPost(
      () => response(
        {
          'item_id': 'item-a',
          'member_id': 'member-1',
          'status': 'paid',
          'decline_reason': null,
        },
        statusCode: 200,
      ),
    );

    final outcome = await repo.retryMembershipCard(req);

    expect(outcome.status, MemberMembershipsRetryCardStatus.paid);
    expect(outcome.isPaid, isTrue);
    expect(outcome.declineReason, isNull);
  });

  test('207: a decline parses as declined + reason, never throws', () async {
    stubPost(
      () => response(
        {
          'item_id': 'item-a',
          'member_id': 'member-1',
          'status': 'declined',
          'decline_reason': 'Your card has insufficient funds.',
        },
        statusCode: 207,
      ),
    );

    final outcome = await repo.retryMembershipCard(req);

    expect(outcome.status, MemberMembershipsRetryCardStatus.declined);
    expect(outcome.isPaid, isFalse);
    expect(outcome.declineReason, 'Your card has insufficient funds.');
  });

  test('207: not-collected is its OWN outcome, not a decline', () async {
    // Nobody refused this card — the charge needs authorization only the
    // member can complete. Before this status existed the value fell through
    // to `unknown`, so the desk saw a generic non-payment and could only
    // guess; retrying at the counter can never settle it, which is why it
    // must not read as `declined`.
    stubPost(
      () => response(
        {
          'item_id': 'item-a',
          'member_id': 'member-1',
          'status': 'not_collected',
          'decline_reason':
              'The card on file could not be charged automatically — the '
              'payment needs extra authorization the member has to '
              'complete. Collect payment another way.',
        },
        statusCode: 207,
      ),
    );

    final outcome = await repo.retryMembershipCard(req);

    expect(outcome.status, MemberMembershipsRetryCardStatus.notCollected);
    expect(outcome.status, isNot(MemberMembershipsRetryCardStatus.declined));
    expect(outcome.status, isNot(MemberMembershipsRetryCardStatus.unknown));
    expect(outcome.isPaid, isFalse);
    expect(outcome.declineReason, contains('extra authorization'));
  });

  test('an unknown status is NOT paid (fail closed)', () async {
    stubPost(
      () => response(
        {
          'item_id': 'item-a',
          'member_id': 'member-1',
          'status': 'something_new',
        },
        statusCode: 207,
      ),
    );

    final outcome = await repo.retryMembershipCard(req);

    expect(outcome.status, MemberMembershipsRetryCardStatus.unknown);
    expect(outcome.isPaid, isFalse);
  });

  test('a 2xx with an unreadable body throws, never reads as paid', () async {
    stubPost(() => response('not json', statusCode: 200));

    expect(
      () => repo.retryMembershipCard(req),
      throwsA(isA<ServerException>()),
    );
  });

  test('409: throws MembershipInTaskException', () async {
    when(
      () => api.post<dynamic>(any(), data: any(named: 'data')),
    ).thenThrow(
      const ServerException(
        'Server error 409: Conflict',
        statusCode: 409,
        detail: 'Membership is inside an unfinished task.',
      ),
    );

    expect(
      () => repo.retryMembershipCard(req),
      throwsA(isA<MembershipInTaskException>()),
    );
  });

  test('500: the system failure rethrows as ServerException', () async {
    when(
      () => api.post<dynamic>(any(), data: any(named: 'data')),
    ).thenThrow(
      const ServerException(
        'Server error 500: Internal Server Error',
        statusCode: 500,
        detail: 'Failed to retry the card on membership',
      ),
    );

    expect(
      () => repo.retryMembershipCard(req),
      throwsA(
        isA<ServerException>().having(
          (e) => e.detail,
          'detail',
          'Failed to retry the card on membership',
        ),
      ),
    );
  });
}
