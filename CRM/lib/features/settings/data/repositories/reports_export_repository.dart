import 'dart:typed_data';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';

/// A downloaded report / export: the zip [bytes] and the resolved save
/// [filename] — the server's `Content-Disposition` name when present, else a
/// client-side fallback matching the backend's v1 filename contract.
typedef ReportDownload = ({Uint8List bytes, String filename});

/// Fetches the gym's operational reports and full data export as zip files
/// from the backend `reports` domain. Layered like every other CRM data path:
/// Screen → (page-scoped state) → Repository → [ApiClient] → backend.
///
/// The endpoints stream a zip body, so each call goes through
/// [ApiClient.getBytes] (raw bytes + a 2-minute receive timeout) rather than
/// the JSON [ApiClient.get]. On any failure the repository throws a
/// [DatabaseException] carrying a friendly message (per the established
/// repository pattern) so the caller can surface a retryable error.
class ReportsExportRepository {
  final ApiClient _apiClient;

  ReportsExportRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/gyms/{gymId}/reports/report?month=YYYY-MM` — the operational
  /// report (financials, membership changes, check-ins) for a single
  /// [month] (1–12, zero-padded in the query) of [year].
  Future<ReportDownload> downloadMonthlyReport({
    required String gymId,
    required int year,
    required int month,
  }) async {
    final monthParam = '$year-${month.toString().padLeft(2, '0')}';
    return _download(
      path: '/api/v1/gyms/$gymId/reports/report',
      queryParameters: {'month': monthParam},
      fallbackFilename: 'combatden_report_gym_$monthParam.zip',
      friendlyMessage:
          'Couldn\'t build the report just now. Nothing was downloaded. '
          'Try again.',
    );
  }

  /// `GET /api/v1/gyms/{gymId}/reports/report` — the same operational report
  /// across the gym's whole history (the `month` query param omitted).
  Future<ReportDownload> downloadAllTimeReport({
    required String gymId,
  }) async {
    return _download(
      path: '/api/v1/gyms/$gymId/reports/report',
      fallbackFilename: 'combatden_report_gym_all-time.zip',
      friendlyMessage:
          'Couldn\'t build the report just now. Nothing was downloaded. '
          'Try again.',
    );
  }

  /// `GET /api/v1/gyms/{gymId}/reports/full-export` — every record the gym has
  /// as raw CSVs, zipped.
  Future<ReportDownload> downloadFullExport({
    required String gymId,
  }) async {
    return _download(
      path: '/api/v1/gyms/$gymId/reports/full-export',
      fallbackFilename: 'combatden_export_gym_${_todayStamp()}.zip',
      friendlyMessage:
          'Couldn\'t build the export just now. Nothing was downloaded. '
          'Try again.',
    );
  }

  Future<ReportDownload> _download({
    required String path,
    required String fallbackFilename,
    required String friendlyMessage,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final result = await _apiClient.getBytes(
        path,
        queryParameters: queryParameters,
      );
      final serverName = result.filename;
      final filename = (serverName != null && serverName.isNotEmpty)
          ? serverName
          : fallbackFilename;
      return (bytes: result.bytes, filename: filename);
    } on ServerException catch (e) {
      throw DatabaseException(
        '$friendlyMessage${e.detail != null ? ' (${e.detail})' : ''}',
      );
    } on NetworkException catch (_) {
      throw DatabaseException(friendlyMessage);
    }
  }

  /// Today's date as `yyyymmdd` (device clock) for the full-export fallback
  /// filename — the server name wins whenever the header is present.
  String _todayStamp() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}
