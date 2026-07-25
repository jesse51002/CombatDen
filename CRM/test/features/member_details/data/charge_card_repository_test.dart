import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

/// Repository-level coverage for `chargeCard`. Only a 204 means the money
/// was collected. A DEFINITIVE non-collection comes back as the backend's
/// 207 result — still a 2xx, so `dio` raises nothing and an unguarded
/// `await` would report a collected charge over money that never moved.
void main() {
  late MockApiClient api;
  late MemberRepository repo;

  Future<void> charge() => repo.chargeCard(
        memberId: 'member-1',
        paidByMemberId: 'payer-1',
        gymId: 'gym-1',
        amount: 2500,
        reason: 'Pro-shop gloves',
        idempotencyKey: 'key-1',
      );

  void stubPost(Object? data, {int? statusCode}) {
    when(
      () => api.post<dynamic>(any(), data: any(named: 'data')),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(
          path: '/api/v1/member_memberships/charge-card',
        ),
        data: data,
        statusCode: statusCode,
      ),
    );
  }

  setUp(() {
    api = MockApiClient();
    repo = MemberRepository(apiClient: api);
  });

  test('204: a collected charge completes normally', () async {
    stubPost(null, statusCode: 204);

    await expectLater(charge(), completes);
  });

  test('207: a non-collection throws, never reads as charged', () async {
    // Nobody refused this card — the payment needs authorization only the
    // member can complete. It is a 2xx, so nothing throws on its own; without
    // the guard the dialog shows a green "charged" for an uncollected charge.
    const reason =
        'The card on file could not be charged automatically — the payment '
        'needs extra authorization the member has to complete. Collect '
        'payment another way.';
    stubPost(
      {
        'member_id': 'member-1',
        'paid_by_member_id': 'payer-1',
        'status': 'not_collected',
        'decline_reason': reason,
      },
      statusCode: 207,
    );

    await expectLater(
      charge(),
      throwsA(
        isA<ServerException>()
            .having((e) => e.statusCode, 'statusCode', 207)
            // The staff-facing reason is what the dialog renders.
            .having((e) => e.detail, 'detail', reason),
      ),
    );
  });

  test('207 with an unreadable body still throws (fail closed)', () async {
    stubPost('not json', statusCode: 207);

    await expectLater(
      charge(),
      throwsA(
        isA<ServerException>().having((e) => e.detail, 'detail', isNull),
      ),
    );
  });

  test('500: the system failure propagates as ServerException', () async {
    when(
      () => api.post<dynamic>(any(), data: any(named: 'data')),
    ).thenThrow(
      const ServerException(
        'Server error 500: Internal Server Error',
        statusCode: 500,
        detail: 'Failed to charge member card',
      ),
    );

    await expectLater(
      charge(),
      throwsA(
        isA<ServerException>().having(
          (e) => e.detail,
          'detail',
          'Failed to charge member card',
        ),
      ),
    );
  });
}
