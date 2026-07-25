import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

/// [ScheduleRepository]'s half of the PAUSED-class contract.
///
/// A paused class (`gym_classes.is_active = false`) is hidden SERVER-side:
/// both `/classes` and `/classes/instances` default `include_inactive` to
/// false, so no occurrence surface can offer an occurrence that check-in and
/// sign-up would reject with `400 class_inactive`. The class-MANAGEMENT read
/// is the one caller that opts in — that is where a paused class is
/// un-paused — so the default, the opt-in, and the occurrence feed's
/// deliberate silence on the flag are all pinned here.
void main() {
  const gymId = 'gym-1';

  late MockApiClient api;
  late ScheduleRepository repo;

  Response<dynamic> envelope(List<Map<String, dynamic>> items) => Response(
        requestOptions: RequestOptions(path: '/'),
        data: <String, dynamic>{'items': items},
      );

  List<dynamic> captureGet() => verify(
        () => api.get<dynamic>(
          captureAny(),
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;

  setUp(() {
    api = MockApiClient();
    repo = ScheduleRepository(apiClient: api);
    when(
      () => api.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => envelope(const []));
  });

  test('listClasses defaults include_inactive to false', () async {
    await repo.listClasses(gymId);

    final captured = captureGet();
    expect(captured[0], '/api/v1/classes');
    expect(captured[1], {'gym_id': gymId, 'include_inactive': false});
  });

  test('listClasses forwards include_inactive: true', () async {
    await repo.listClasses(gymId, includeInactive: true);

    final captured = captureGet();
    expect(captured[1], {'gym_id': gymId, 'include_inactive': true});
  });

  test('listEffectiveInstances defaults include_inactive to false', () async {
    // Every non-board caller (dashboard, kiosk, member check-in dialog) uses
    // the default, and false is what keeps them paused-free.
    await repo.listEffectiveInstances(
      gymId,
      DateTime(2026, 6, 1),
      DateTime(2026, 6, 7),
    );

    final captured = captureGet();
    expect(captured[0], '/api/v1/classes/instances');
    expect(captured[1], {
      'gym_id': gymId,
      'start_date': '2026-06-01',
      'end_date': '2026-06-07',
      'include_inactive': false,
    });
  });

  test('listEffectiveInstances forwards include_inactive: true', () async {
    // The schedule board is the ONE caller that opts in — that is how paused
    // occurrences reach the classes page and nowhere else.
    await repo.listEffectiveInstances(
      gymId,
      DateTime(2026, 6, 1),
      DateTime(2026, 6, 7),
      includeInactive: true,
    );

    final captured = captureGet();
    expect((captured[1] as Map<String, dynamic>)['include_inactive'], isTrue);
  });
}
