import 'package:dio/dio.dart';

import 'package:mobile_app/features/gym/data/gym_detail.dart';

/// Thrown on any gym-detail fetch failure; the repository catches it and
/// degrades (empty classes / rewards).
class GymFetchException implements Exception {
  final String message;
  const GymFetchException(this.message);

  @override
  String toString() => message;
}

/// Read-only client for the VideoService gym detail. Mirrors `VideoApiClient`
/// (same host, short timeouts). One call returns the gym's whole content
/// (classes + rewards) for the member app to hold in memory.
class GymApiClient {
  GymApiClient({required this.baseUrl, required this.gymId}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {'Accept': 'application/json'},
      ),
    );
  }

  final String baseUrl;
  final String gymId;

  late final Dio _dio;

  /// `GET /gyms/{gymId}` — the gym's whole content detail.
  Future<GymDetail> fetchDetail() async {
    try {
      final response = await _dio.get<dynamic>('/gyms/$gymId');
      final data = response.data;
      if (data is Map) {
        return GymDetail.fromJson(Map<String, dynamic>.from(data));
      }
      throw const GymFetchException('Gym detail response was not an object');
    } on DioException catch (e) {
      throw GymFetchException('Gym detail fetch failed: ${e.message}');
    }
  }
}
