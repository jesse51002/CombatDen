import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';

/// Persists a gym's chosen ThemeService design id through the FastApiBackend.
/// Layered like every other CRM data path:
/// Screen → Bloc → Repository → [ApiClient] → backend.
class GymThemeRepository {
  final ApiClient _apiClient;

  GymThemeRepository(ApiClient apiClient) : _apiClient = apiClient;

  /// `PUT /api/v1/gyms/{gymId}/theme` — save the gym's chosen ThemeService
  /// design id (`gyms.theme_design_id`), the branding shown in the gym's member
  /// app. Gym-employee gated on the backend. Throws [DatabaseException] on any
  /// failure so the bloc can surface the error.
  Future<void> saveGymTheme({
    required String gymId,
    required String themeDesignId,
  }) async {
    try {
      await _apiClient.put<dynamic>(
        '/api/v1/gyms/$gymId/theme',
        data: {
          'data': {'theme_design_id': themeDesignId},
        },
      );
    } on ServerException catch (e) {
      throw DatabaseException(
        'Couldn\'t save the app theme. Please try again.${e.detail != null ? ' (${e.detail})' : ''}',
      );
    } on NetworkException catch (e) {
      throw DatabaseException(e.message);
    }
  }
}
