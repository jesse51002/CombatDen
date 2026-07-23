import 'dart:developer';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/growth/data/models/growth_metric.dart';

/// Repository for the growth (per-gym analytics) domain.
///
/// Wraps [ApiClient] for the Growth page's single cached read. The metrics
/// are recomputed on the backend's own clock — this endpoint never computes,
/// so the CRM only ever reads.
///
/// Layered per CRM convention:
///   Screen → Bloc → GrowthRepository → ApiClient → backend.
class GrowthRepository {
  final ApiClient _apiClient;

  GrowthRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// `GET /api/v1/growth/?gym_id=<uuid>`
  ///
  /// Metrics the CRM cannot render (unknown type, payload that does not fit
  /// its model) are skipped by [GrowthPage.fromJson] rather than failing the
  /// whole read — see that factory for the fault-tolerance contract.
  Future<GrowthPage> getGrowth(String gymId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/growth/',
        queryParameters: {'gym_id': gymId},
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      if (data['metrics'] is! List) {
        throw const ServerException('Missing metrics array');
      }
      return GrowthPage.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('getGrowth failed', error: e, stackTrace: st);
      throw ServerException('Failed to load growth metrics: $e');
    }
  }
}
