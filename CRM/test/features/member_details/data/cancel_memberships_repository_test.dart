import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

/// Repository-level coverage for `cancelMemberships`: a 207 Multi-Status
/// partial-cancel body (top-level `{succeeded_item_ids: [...],
/// failed_item_ids: [...]}` — a 207 is a returned RESULT, not an
/// HTTPException, so there is no `detail` wrapper) is parsed into the real
/// succeeded/failed split; a 200 reports every item succeeded; a 409
/// throws; and a total failure (500) reports all items failed.
void main() {
  const memberId = 'member-1';
  const itemId1 = 'item-a';
  const itemId2 = 'item-b';

  late MockApiClient api;
  late MemberRepository repo;

  Response<dynamic> response(Object? data, {int? statusCode}) =>
      Response<dynamic>(
        requestOptions: RequestOptions(path: '/api/v1/member_memberships/'),
        data: data,
        statusCode: statusCode,
      );

  setUp(() {
    api = MockApiClient();
    repo = MemberRepository(apiClient: api);
  });

  test('200: all requested items succeed from cancel_dates keys', () async {
    when(
      () => api.delete<dynamic>(any(), data: any(named: 'data')),
    ).thenAnswer(
      (_) async => response({
        'cancel_dates': {itemId1: '2026-07-01', itemId2: '2026-07-01'},
      }),
    );

    final outcome = await repo.cancelMemberships(
      itemIds: const [itemId1, itemId2],
      memberId: memberId,
      idempotencyKey: 'key-1',
    );

    expect(outcome.succeededItemIds, containsAll([itemId1, itemId2]));
    expect(outcome.failedItemIds, isEmpty);
  });

  test(
    '207 partial: parses the top-level split into succeeded/failed',
    () async {
      when(
        () => api.delete<dynamic>(any(), data: any(named: 'data')),
      ).thenAnswer(
        (_) async => response(
          {
            'message': 'Cancel partially applied',
            'succeeded_item_ids': [itemId1],
            'failed_item_ids': [itemId2],
          },
          statusCode: 207,
        ),
      );

      final outcome = await repo.cancelMemberships(
        itemIds: const [itemId1, itemId2],
        memberId: memberId,
        idempotencyKey: 'key-1',
      );

      expect(outcome.succeededItemIds, [itemId1]);
      expect(outcome.failedItemIds, [itemId2]);
      expect(outcome.isPartial, isTrue);
    },
  );

  test(
    '500 total failure: every item reported as failed',
    () async {
      when(
        () => api.delete<dynamic>(any(), data: any(named: 'data')),
      ).thenThrow(
        const ServerException(
          'Server error 500: Internal Server Error',
          statusCode: 500,
          detail: 'Stripe is down',
        ),
      );

      final outcome = await repo.cancelMemberships(
        itemIds: const [itemId1, itemId2],
        memberId: memberId,
        idempotencyKey: 'key-1',
      );

      expect(outcome.succeededItemIds, isEmpty);
      expect(outcome.failedItemIds, containsAll([itemId1, itemId2]));
    },
  );

  test('409: throws MembershipInTaskException', () async {
    when(
      () => api.delete<dynamic>(any(), data: any(named: 'data')),
    ).thenThrow(
      const ServerException(
        'Server error 409: Conflict',
        statusCode: 409,
        detail: 'Membership is inside an unfinished task.',
      ),
    );

    expect(
      () => repo.cancelMemberships(
        itemIds: const [itemId1],
        memberId: memberId,
        idempotencyKey: 'key-1',
      ),
      throwsA(isA<MembershipInTaskException>()),
    );
  });
}
