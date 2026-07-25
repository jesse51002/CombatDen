import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

/// [MembersListRepository]'s half of the Incomplete-view contract: the
/// request must carry `view: "incomplete"` (the backend dispatches the
/// row shape off it) and the response's rows must come back as
/// [IncompleteViewRow]s.
void main() {
  const gymId = 'gym-1';

  late _MockApiClient api;
  late MembersListRepository repo;

  Response<dynamic> body(Map<String, dynamic> data) => Response(
        requestOptions: RequestOptions(path: '/'),
        data: data,
      );

  setUp(() {
    api = _MockApiClient();
    repo = MembersListRepository(apiClient: api);
  });

  test(
    'getMembersList sends the incomplete view and parses its rows',
    () async {
      when(
        () => api.post<dynamic>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => body(<String, dynamic>{
          'view': 'incomplete',
          'filters': <String, dynamic>{},
          'data': [
            <String, dynamic>{
              'view': 'incomplete',
              'member_id': 'mem-9',
              'name': 'Sam Okafor',
              'email': 'sam@example.com',
              'phone': '+1 555 0111',
              'days_waiting': 12,
            },
          ],
        }),
      );

      final response = await repo.getMembersList(
        const CrmMembersListRequest(
          gymId: gymId,
          view: MembersListView.incomplete,
        ),
      );

      final captured = verify(
        () => api.post<dynamic>(
          captureAny(),
          data: captureAny(named: 'data'),
        ),
      ).captured;

      expect(captured[0], '/api/v1/members/list');
      final sent = captured[1] as Map<String, dynamic>;
      expect(sent['gym_id'], gymId);
      expect(sent['view'], 'incomplete');

      expect(response.view, MembersListView.incomplete);
      expect(response.data, hasLength(1));
      final row = response.data.single as IncompleteViewRow;
      expect(row.memberId, 'mem-9');
      expect(row.name, 'Sam Okafor');
      expect(row.email, 'sam@example.com');
      expect(row.phone, '+1 555 0111');
      expect(row.daysWaiting, 12);
    },
  );

  test(
    'getTotalCounts reads the incomplete tally off the counts endpoint',
    () async {
      when(
        () => api.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => body(<String, dynamic>{
          'active': 5,
          'trial': 2,
          'frozen': 0,
          'overdue': 1,
          'dormant': 3,
          'incomplete': 4,
        }),
      );

      final counts = await repo.getTotalCounts(gymId);

      final captured = verify(
        () => api.get<dynamic>(
          captureAny(),
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;

      expect(captured[0], '/api/v1/members/counts');
      expect(captured[1], {'gym_id': gymId});
      expect(counts.incomplete, 4);
    },
  );
}
