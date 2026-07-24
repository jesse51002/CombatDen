import 'dart:typed_data';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/settings/data/repositories/reports_export_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

/// Repository-level coverage for [ReportsExportRepository]: the raw bytes pass
/// straight through, the month query is zero-padded, the server-provided
/// filename wins over the client fallback (and the fallback is used when the
/// header is absent), and backend failures map to a [DatabaseException].
void main() {
  const gymId = 'gym-1';
  final bytes = Uint8List.fromList([1, 2, 3, 4]);

  late MockApiClient api;
  late ReportsExportRepository repo;

  BytesResponse resp({String? filename}) =>
      (bytes: bytes, filename: filename);

  setUp(() {
    api = MockApiClient();
    repo = ReportsExportRepository(apiClient: api);
  });

  test('monthly: passes bytes through and uses the server filename', () async {
    when(
      () => api.getBytes(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => resp(filename: 'server_name.zip'));

    final download = await repo.downloadMonthlyReport(
      gymId: gymId,
      year: 2026,
      month: 6,
    );

    expect(download.bytes, same(bytes));
    expect(download.filename, 'server_name.zip');
  });

  test('monthly: zero-pads the month in the query', () async {
    when(
      () => api.getBytes(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => resp(filename: 'x.zip'));

    await repo.downloadMonthlyReport(gymId: gymId, year: 2026, month: 6);

    final captured = verify(
      () => api.getBytes(
        captureAny(),
        queryParameters: captureAny(named: 'queryParameters'),
      ),
    ).captured;
    expect(captured[0], '/api/v1/gyms/$gymId/reports/report');
    expect(captured[1], {'month': '2026-06'});
  });

  test('monthly: falls back to a client filename when header absent', () async {
    when(
      () => api.getBytes(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => resp(filename: null));

    final download = await repo.downloadMonthlyReport(
      gymId: gymId,
      year: 2026,
      month: 6,
    );

    expect(download.filename, 'combatden_report_gym_2026-06.zip');
  });

  test('all-time: omits the month param and uses the all-time fallback',
      () async {
    when(
      () => api.getBytes(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => resp(filename: null));

    final download = await repo.downloadAllTimeReport(gymId: gymId);

    expect(download.filename, 'combatden_report_gym_all-time.zip');
    final captured = verify(
      () => api.getBytes(
        captureAny(),
        queryParameters: captureAny(named: 'queryParameters'),
      ),
    ).captured;
    expect(captured[0], '/api/v1/gyms/$gymId/reports/report');
    expect(captured[1], isNull);
  });

  test('full export: hits full-export and uses the dated fallback', () async {
    when(
      () => api.getBytes(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => resp(filename: null));

    final download = await repo.downloadFullExport(gymId: gymId);

    expect(
      download.filename,
      matches(RegExp(r'^combatden_export_gym_\d{8}\.zip$')),
    );
    final captured = verify(
      () => api.getBytes(
        captureAny(),
        queryParameters: captureAny(named: 'queryParameters'),
      ),
    ).captured;
    expect(captured[0], '/api/v1/gyms/$gymId/reports/full-export');
  });

  test('ServerException maps to DatabaseException with the detail appended',
      () async {
    when(
      () => api.getBytes(any(), queryParameters: any(named: 'queryParameters')),
    ).thenThrow(
      const ServerException(
        'Server error 500: Internal Server Error',
        statusCode: 500,
        detail: 'boom',
      ),
    );

    await expectLater(
      () => repo.downloadMonthlyReport(gymId: gymId, year: 2026, month: 6),
      throwsA(
        isA<DatabaseException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Nothing was downloaded'), contains('boom')),
        ),
      ),
    );
  });

  test('NetworkException maps to a friendly DatabaseException', () async {
    when(
      () => api.getBytes(any(), queryParameters: any(named: 'queryParameters')),
    ).thenThrow(const NetworkException('Network error: connection refused'));

    await expectLater(
      () => repo.downloadFullExport(gymId: gymId),
      throwsA(
        isA<DatabaseException>().having(
          (e) => e.message,
          'message',
          contains('Nothing was downloaded'),
        ),
      ),
    );
  });
}
