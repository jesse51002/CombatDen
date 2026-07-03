import 'package:flutter/material.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/theme_controller.dart';

/// Persists CRM settings through the FastApiBackend — the caller's appearance
/// (theme) preference on their `gym_employees` row and the gym's timezone on
/// the gym row. Layered like every other CRM data path:
/// Screen → Bloc → Repository → [ApiClient] → backend.
class SettingsRepository {
  final ApiClient _apiClient;

  SettingsRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `PUT /api/v1/gyms/{gymId}/employees/me/theme` — save the caller's theme
  /// preference for [gymId]. Throws [DatabaseException] on any failure so the
  /// bloc can revert the optimistic update.
  Future<void> updateMyTheme({
    required String gymId,
    required ThemeMode mode,
  }) async {
    try {
      await _apiClient.put<dynamic>(
        '/api/v1/gyms/$gymId/employees/me/theme',
        data: {
          'data': {'theme_preference': themeModeToApi(mode)},
        },
      );
    } on ServerException catch (e) {
      throw DatabaseException(
        'Couldn\'t save your theme. Please try again.${e.detail != null ? ' (${e.detail})' : ''}',
      );
    } on NetworkException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// `PUT /api/v1/gyms/{gymId}` — save the gym's IANA [timezone]. The backend
  /// re-mints every class's schedule version in the new zone (nothing is
  /// wiped; upcoming classes keep their local times). Throws
  /// [DatabaseException] on any failure so the bloc can surface the error.
  Future<void> updateGymTimezone({
    required String gymId,
    required String timezone,
  }) async {
    try {
      await _apiClient.put<dynamic>(
        '/api/v1/gyms/$gymId',
        data: {
          'data': {'timezone': timezone},
        },
      );
    } on ServerException catch (e) {
      throw DatabaseException(
        'Couldn\'t update the gym timezone. Please try again.${e.detail != null ? ' (${e.detail})' : ''}',
      );
    } on NetworkException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// `PUT /api/v1/gyms/{gymId}` — save the gym's identity: its [gymName] and
  /// [logoUrl] (the uploaded brand logo's CDN URL; an explicit null clears the
  /// logo). Patch semantics — both fields are sent together, so pass the
  /// current logo unchanged when only the name is edited. Throws
  /// [DatabaseException] on any failure so the bloc can surface the error.
  Future<void> updateGymProfile({
    required String gymId,
    required String gymName,
    required String? logoUrl,
  }) async {
    try {
      await _apiClient.put<dynamic>(
        '/api/v1/gyms/$gymId',
        data: {
          'data': {'gym_name': gymName, 'logo_url': logoUrl},
        },
      );
    } on ServerException catch (e) {
      throw DatabaseException(
        'Couldn\'t update your gym profile. Please try again.${e.detail != null ? ' (${e.detail})' : ''}',
      );
    } on NetworkException catch (e) {
      throw DatabaseException(e.message);
    }
  }
}
