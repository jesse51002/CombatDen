import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

/// Repository-level coverage for `cancelMemberships` — specifically that the
/// structured 502 partial-cancel body (`{"detail": {"succeeded_item_ids":
/// [...], "failed_item_ids": [...]}}`) is parsed into the real
/// succeeded/failed split, instead of the old all-failed fallback.
void main() {
  const memberId = 'member-1';
  const itemId1 = 'item-a';
  const itemId2 = 'item-b';

  late MockApiClient api;
  late MemberRepository repo;

  Response<dynamic> response(Object? data) => Response<dynamic>(
        requestOptions: RequestOptions(path: '/api/v1/member_memberships/'),
        data: data,
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
    '502 partial: parses the structured detail into the real split',
    () async {
      when(
        () => api.delete<dynamic>(any(), data: any(named: 'data')),
      ).thenThrow(
        const ServerException(
          'Server error 502: Bad Gateway',
          statusCode: 502,
          data: {
            'detail': {
              'message': 'Cancel partially applied',
              'succeeded_item_ids': [itemId1],
              'failed_item_ids': [itemId2],
            },
          },
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
    '502 unstructured (string detail): falls back to all-failed',
    () async {
      when(
        () => api.delete<dynamic>(any(), data: any(named: 'data')),
      ).thenThrow(
        const ServerException(
          'Server error 502: Bad Gateway',
          statusCode: 502,
          detail: 'Stripe is down',
          data: {'detail': 'Stripe is down'},
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
