import 'package:flutter/material.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/theme_controller.dart';

/// Persists per-employee CRM settings through the FastApiBackend.
///
/// Today this is just the appearance (theme) preference, saved on the caller's
/// `gym_employees` row. Layered like every other CRM data path:
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
}
