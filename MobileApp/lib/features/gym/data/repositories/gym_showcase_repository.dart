import 'dart:developer';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/gym/data/models/gym_showcase.dart';

/// Repository for the gym showcase read — the source of the gym's saved
/// ThemeService design id used to re-theme the app.
///
/// Layered per convention: Gate → GymShowcaseRepository → ApiClient → backend.
class GymShowcaseRepository {
  final ApiClient _apiClient;

  GymShowcaseRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/gyms/{gym_id}/showcase` → the gym's [GymShowcase] (its
  /// [GymShowcase.themeDesignId] is the field the app applies). Throws the
  /// typed [NetworkException] / [ServerException] on failure.
  Future<GymShowcase> fetchShowcase(String gymId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/gyms/$gymId/showcase',
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return GymShowcase.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('fetchShowcase failed', error: e, stackTrace: st);
      throw ServerException('Failed to load gym showcase: $e');
    }
  }
}
