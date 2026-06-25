import 'dart:developer';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/presets/data/models/preset_models.dart';

/// Repository for the presets domain.
///
/// Wraps [ApiClient] for both the public template catalog browse
/// and the authed preset import. Both go through the same FastApiBackend,
/// so [ApiClient] is the right client (not `package:http` directly).
///
/// Layered per CRM convention:
///   Screen → Bloc → PresetsRepository → ApiClient → backend.
class PresetsRepository {
  final ApiClient _apiClient;

  PresetsRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/videos/templates` — the first page of the template catalog.
  ///
  /// Loads up to [limit] templates (default 100 — the full catalog fits in one
  /// page today; pagination can be wired later). Returns slim [TemplateCard]s
  /// for the picker UI. Throws [ServerException] / [NetworkException] on failure.
  Future<List<TemplateCard>> listTemplates({
    String? query,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/videos/templates',
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (query != null && query.isNotEmpty) 'query': query,
        },
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      final rawGyms = data['gyms'];
      if (rawGyms is! List) {
        throw const ServerException('Missing gyms array in response');
      }
      return rawGyms
          .whereType<Map>()
          .map((e) => TemplateCard.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('listTemplates failed', error: e, stackTrace: st);
      throw ServerException('Failed to load templates: $e');
    }
  }

  /// `POST /api/v1/gyms/{gymId}/presets/import` — import a template into the
  /// real gym. The backend enforces an allowlist (owner1@test.com + gym owner
  /// role). Throws [ServerException] / [NetworkException] on failure.
  Future<PresetImportResult> importPreset({
    required String gymId,
    required String videoGymId,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/gyms/$gymId/presets/import',
        data: {'video_gym_id': videoGymId},
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return PresetImportResult.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('importPreset failed', error: e, stackTrace: st);
      throw ServerException('Failed to import preset: $e');
    }
  }
}
