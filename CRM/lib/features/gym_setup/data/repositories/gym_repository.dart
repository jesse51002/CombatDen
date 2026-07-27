import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/gym_setup/data/models/gym_create_request.dart';
import 'package:crm/features/gym_setup/data/models/gym_create_response.dart';
import 'package:crm/features/gym_setup/data/models/gym_onboarding_link_response.dart';
import 'package:crm/features/gym_setup/data/models/gym_onboarding_status_response.dart';
import 'package:crm/features/gym_setup/data/models/gym_with_role.dart';
import 'package:dio/dio.dart';

/// Repository mediating all gym-creation traffic
/// through the FastAPI backend.
///
/// Supabase writes to `gyms` and `gym_employees` are
/// RLS-revoked; every mutation must go through these
/// endpoints. See `FastApiBackend/src/gyms/notes/` for
/// the full contract.
class GymRepository {
  final ApiClient _apiClient;

  GymRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `POST /api/v1/gyms/` — create a gym and mint the
  /// first Stripe onboarding URL.
  ///
  /// Throws [GymConflictException] on `409`, preserving
  /// the `detail` string so the caller can switch on
  /// the three contract values. Throws
  /// [DatabaseException] for every other failure mode
  /// with a user-facing message.
  ///
  /// [address] is optional — pass null when the owner
  /// skipped the wizard's address field.
  Future<GymCreateResponse> createGym({
    required String gymName,
    String? address,
    required String firstName,
    required String lastName,
  }) async {
    final request = GymCreateRequest(
      gymName: gymName,
      address: address,
      ownerFirstName: firstName,
      ownerLastName: lastName,
    );
    try {
      final response = await _apiClient.post<dynamic>(
        '/api/v1/gyms/',
        data: request.toJson(),
      );
      return GymCreateResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409 && e.detail != null) {
        throw GymConflictException(e.detail!);
      }
      throw DatabaseException(_userFacingMessage(e));
    } on NetworkException catch (e) {
      throw DatabaseException(e.message);
    } on DioException catch (e) {
      throw DatabaseException(
        'Unexpected error: ${e.message}',
      );
    }
  }

  /// `GET /api/v1/gyms/` — the gyms the signed-in user owns or
  /// admins, each annotated with the caller's role.
  ///
  /// Returns an empty list when the user administers no gyms (→
  /// route to the setup wizard). The app's auth gate calls this once
  /// after sign-in to choose the active gym (one → straight in;
  /// several → the gym picker) and seed it. Throws
  /// [DatabaseException] on any failure.
  Future<List<GymWithRole>> getMyGyms() async {
    try {
      final response = await _apiClient.get<dynamic>(
        '/api/v1/gyms/',
      );
      final list = response.data as List<dynamic>;
      return list
          .map(
            (e) => GymWithRole.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on ServerException catch (e) {
      throw DatabaseException(_userFacingMessage(e));
    } on NetworkException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// `GET /api/v1/gyms/{gymId}/onboarding` — refresh the
  /// gym's Stripe onboarding status. Owner-only on the backend.
  ///
  /// Returns `null` when the backend returns `404`
  /// (gym not found, or the Stripe account vanished).
  /// Throws [DatabaseException] on any other failure.
  Future<GymOnboardingStatusResponse?> getOnboardingStatus(
    String gymId,
  ) async {
    try {
      final response = await _apiClient.get<dynamic>(
        '/api/v1/gyms/$gymId/onboarding',
      );
      return GymOnboardingStatusResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on ServerException catch (e) {
      if (e.statusCode == 404) {
        return null;
      }
      throw DatabaseException(_userFacingMessage(e));
    } on NetworkException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// `POST /api/v1/gyms/{gymId}/onboarding/link` — mint a
  /// fresh hosted URL without re-reading Stripe. Owner-only.
  ///
  /// Valid only while the gym is still `pending`. A
  /// `409` here means the status has flipped; the
  /// caller should re-fetch via [getOnboardingStatus].
  Future<GymOnboardingLinkResponse> refreshOnboardingLink(
    String gymId,
  ) async {
    try {
      final response = await _apiClient.post<dynamic>(
        '/api/v1/gyms/$gymId/onboarding/link',
      );
      return GymOnboardingLinkResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on ServerException catch (e) {
      throw DatabaseException(_userFacingMessage(e));
    } on NetworkException catch (e) {
      throw DatabaseException(e.message);
    }
  }

  /// Maps a backend [ServerException] to copy suitable
  /// for showing to the end user. Mirrors the HTTP
  /// status → UX mapping in
  /// `05_error_handling.md`.
  String _userFacingMessage(ServerException e) {
    switch (e.statusCode) {
      case 400:
        return 'Please check your info and try again.';
      case 401:
        return 'Your session has expired. '
            'Please sign in again.';
      case 502:
        return 'Stripe is unavailable right now. '
            'Please try again.';
      case 500:
        return 'Something went wrong. '
            'Please try again.';
      default:
        return 'Something went wrong. '
            'Please try again.';
    }
  }
}
