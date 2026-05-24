import 'package:dio/dio.dart';

import 'package:mobile_app/features/class_booking/data/class_info.dart';

/// Thrown on any class fetch failure; the repository catches it and degrades
/// to an empty list.
class ClassFetchException implements Exception {
  final String message;
  const ClassFetchException(this.message);

  @override
  String toString() => message;
}

/// Read-only client for the VideoService class cards. Mirrors
/// `VideoApiClient` (same host, short timeouts).
class ClassApiClient {
  ClassApiClient({required this.baseUrl, required this.videoAppId}) {
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
  final String videoAppId;

  late final Dio _dio;

  /// `GET /apps/{videoAppId}/classes` — the tenant's four branded class cards.
  Future<List<ClassInfo>> fetchClasses() async {
    try {
      final response = await _dio.get<dynamic>('/apps/$videoAppId/classes');
      final data = response.data;
      if (data is Map && data['classes'] is List) {
        return (data['classes'] as List)
            .whereType<Map>()
            .map((e) => ClassInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      }
      throw const ClassFetchException(
        'Classes response was not a JSON object with a classes array',
      );
    } on DioException catch (e) {
      throw ClassFetchException('Classes fetch failed: ${e.message}');
    }
  }
}
