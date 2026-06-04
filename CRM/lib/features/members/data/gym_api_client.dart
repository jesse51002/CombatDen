import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:crm/features/members/data/gym_detail.dart';

/// Read-only client for the VideoService gym detail (`GET /gyms/{gymId}`).
///
/// Part of the read-only VideoService carve-out (alongside `VideoApiClient`).
/// The selected gym is fetched once and held in [SelectedGym] memory, so the
/// loyalty store, the videos content focus, the phone preview, the Schedule
/// screen, and the dashboard's Upcoming Classes card all read its
/// rewards / classes / spec without further calls. Base URL mirrors the video
/// carve-out: override with `--dart-define=VIDEO_BASE_URL=http://<host>:8002`.
class GymApiClient {
  GymApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _kDefaultBaseUrl;

  final String baseUrl;

  static const String _kDefaultBaseUrl = String.fromEnvironment(
    'VIDEO_BASE_URL',
    defaultValue: 'http://localhost:8002',
  );

  /// `GET /gyms/{gymId}` — the gym's whole content detail. Throws on failure so
  /// the caller can show an error state (the preview degrades to its samples).
  Future<GymDetail> fetchGym(String gymId) async {
    final uri = Uri.parse('$baseUrl/gyms/$gymId');
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Gym detail fetch failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is Map) {
      return GymDetail.fromJson(Map<String, dynamic>.from(data));
    }
    throw Exception('Gym detail response was not an object');
  }
}
